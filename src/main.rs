use speedyG::executor::Executor;
use speedyG::parser::parse;
use speedyG::persistence::{cargar_scheduler, guardar_scheduler};
use speedyG::scheduler::Scheduler;
use std::fs;
use std::sync::{Arc, Mutex, MutexGuard};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::UnixListener;
use tracing::{error, info, warn};


type SharedScheduler = Arc<Mutex<Scheduler>>;


fn lock(s: &SharedScheduler) -> MutexGuard<'_, Scheduler> {
    s.lock().unwrap_or_else(|e| {
        warn!("Mutex del Scheduler envenenado; se recupera el estado");
        e.into_inner()
    })
}


fn persistir(sched: &Scheduler) {
    if let Err(e) = guardar_scheduler(sched) {
        error!("Error al guardar scheduler: {}", e);
    }
}


fn lanzar_job(scheduler: SharedScheduler, job_id: u32, full_command: String) {
    tokio::spawn(async move {
        //  Pasar a Running. Si el Job ya no está en cola (p. ej. lo cancelaron) NO se ejecuta.
        {
            let mut sched = lock(&scheduler);
            if !sched.start_job(job_id) {
                warn!("Job #{} ya no está en cola (¿cancelado?); no se ejecuta", job_id);
                return;
            }
            persistir(&sched);
        }

        //  Ejecutar (mientras tanto, `status` mostrará Running)
        info!("Job #{} ejecutando: {}", job_id, full_command);
        let exec_result = Executor::run(&full_command).await;

        //  Marcar como completado y guardar. Si lo cancelaron mientras corría,
        //    complete_job devuelve false y se conserva el estado Canceled.
        let mut sched = lock(&scheduler);
        if sched.complete_job(job_id, exec_result.exit_code) {
            info!("Job #{} terminó con código {}", job_id, exec_result.exit_code);
            persistir(&sched);
        } else {
            info!("Job #{} terminó pero ya estaba cancelado; se ignora el resultado", job_id);
        }
    });
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Inicializar el logger
    tracing_subscriber::fmt::init();

    let socket_path = "/tmp/speedyg.sock";

    // Eliminar el socket si quedó de una ejecución previa
    if fs::metadata(socket_path).is_ok() {
        fs::remove_file(socket_path)?;
    }

    let listener = UnixListener::bind(socket_path)?;
    info!("Demonio speedyG escuchando en {}", socket_path);

    // Scheduler compartido entre las conexiones. Se carga de SQLite/JSON.
    let scheduler: SharedScheduler = Arc::new(Mutex::new(cargar_scheduler()));

    // Recuperación tras reinicio: Running -> Failed(-1); Queued, se vuelve a lanzar.
    let por_relanzar = {
        let mut sched = lock(&scheduler);
        let ids = sched.recuperar_tras_reinicio();
        persistir(&sched);
        ids.into_iter()
            .filter_map(|id| sched.get_job(id).map(|j| (id, j.get_command_line())))
            .collect::<Vec<_>>()
    };
    for (id, comando) in por_relanzar {
        info!("Relanzando Job #{} recuperado: {}", id, comando);
        lanzar_job(Arc::clone(&scheduler), id, comando);
    }

    loop {
        let (mut stream, _) = listener.accept().await?;
        let scheduler = Arc::clone(&scheduler);

        tokio::spawn(async move {
            let mut buffer = [0; 1024];

            let n = match stream.read(&mut buffer).await {
                Ok(0) => return, // Conexión cerrada
                Ok(n) => n,
                Err(e) => {
                    error!("Error al leer del socket: {}", e);
                    return;
                }
            };

            let input = String::from_utf8_lossy(&buffer[..n]);
            let input_str = input.trim();

            // Decodificar la entrada usando el parser
            let response = match parse(input_str) {
                Ok(cmd) => match cmd.program.as_str() {
                    "health" => "OK: Daemon speedyg funcionando correctamente\n".to_string(),
                    "help" => {
                        "Comandos disponibles: health, help, status [id], cancel <id>, echo, sleep, ls\n"
                            .to_string()
                    }
                    "status" => {
                        let sched = lock(&scheduler);
                        if let Some(id_str) = cmd.args.first() {
                            // Caso: status <id>
                            match id_str.parse::<u32>() {
                                Ok(id) => match sched.get_job(id) {
                                    Some(job) => format!("{}\n", job),
                                    None => format!("Error: Job #{} no encontrado\n", id),
                                },
                                Err(_) => {
                                    "Error: El ID debe ser un número entero positivo\n".to_string()
                                }
                            }
                        } else {
                            // Caso: status general (lista de jobs)
                            let pending = sched.pending_jobs();
                            let history = sched.history_jobs();

                            if pending.is_empty() && history.is_empty() {
                                "No hay jobs registrados.\n".to_string()
                            } else {
                                let mut out = String::new();
                                if !pending.is_empty() {
                                    out.push_str("--- Pendientes / En ejecución ---\n");
                                    for job in pending {
                                        out.push_str(&format!("{}\n", job));
                                    }
                                }
                                if !history.is_empty() {
                                    out.push_str("--- Historial ---\n");
                                    for job in history {
                                        out.push_str(&format!("{}\n", job));
                                    }
                                }
                                out
                            }
                        }
                    }
                    "cancel" => {
                        if let Some(id_str) = cmd.args.first() {
                            match id_str.parse::<u32>() {
                                Ok(id) => {
                                    let mut sched = lock(&scheduler);
                                    if sched.cancel_job(id) {
                                        // Reflejar la cancelación en persistencia
                                        persistir(&sched);
                                        info!("Job #{} cancelado", id);
                                        format!("Job #{} cancelado correctamente\n", id)
                                    } else {
                                        format!("Error: No se pudo cancelar el Job #{}\n", id)
                                    }
                                }
                                Err(_) => {
                                    "Error: El ID debe ser un número entero positivo\n".to_string()
                                }
                            }
                        } else {
                            "Uso: cancel <id>\n".to_string()
                        }
                    }
                    // Comandos de ejecución (echo, sleep, ls, etc.)
                    _ => {
                        let (job_id, full_command) = {
                            let mut sched = lock(&scheduler);
                            let job = sched.add_job(cmd.program.clone(), cmd.args.clone());
                            let job_id = job.get_id();
                            let full_command = job.get_command_line();

                            // Guardar cambios después de agregar
                            persistir(&sched);
                            (job_id, full_command)
                        };

                        // Tarea asíncrona en segundo plano sin bloquear el socket
                        lanzar_job(Arc::clone(&scheduler), job_id, full_command);

                        // Respuesta inmediata al cliente CLI
                        format!("Job #{} encolado correctamente\n", job_id)
                    }
                },
                Err(err_msg) => format!("Error de sintaxis: {}\n", err_msg),
            };

            // Responder al cliente CLI
            if let Err(e) = stream.write_all(response.as_bytes()).await {
                error!("Error al escribir en el socket: {}", e);
            }
        });
    }
}


