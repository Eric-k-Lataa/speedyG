use speedyG::executor::Executor;
use speedyG::parser::parse;
use speedyG::scheduler::Scheduler;
use std::fs;
use std::sync::{Arc, Mutex};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::UnixListener;
use tracing::{error, info};
use speedyG::persistence::{guardar_scheduler, cargar_scheduler};

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

    // Scheduler compartido entre las conexiones que entran por el socket
    let scheduler = Arc::new(Mutex::new(
        cargar_scheduler().unwrap_or_else(|_| Scheduler::new())
    ));

    loop {
        let (mut stream, _) = listener.accept().await?;
        let scheduler = Arc::clone(&scheduler);

        tokio::spawn(async move {
            let mut buffer = [0; 1024];

            let n = match stream.read(&mut buffer).await {
                Ok(n) if n == 0 => return, // Conexión cerrada
                Ok(n) => n,
                Err(e) => {
                    error!("Error al leer del socket: {}", e);
                    return;
                }
            };

            let input = String::from_utf8_lossy(&buffer[..n]);
            let input_str = input.trim();

            // 1. Decodificar la entrada usando el parser
            let response = match parse(input_str) {
                Ok(cmd) => match cmd.program.as_str() {//Corregi la G a g
                    "health" => "OK: Daemon speedyg funcionando correctamente\n".to_string(),
                    "help" => {
                        "Comandos disponibles: health, help, status [id], cancel <id>, echo, sleep, ls\n"
                            .to_string()
                    }
                    "status" => {
                        let sched = scheduler.lock().unwrap();
                        if let Some(id_str) = cmd.args.get(0) {
                            match id_str.parse::<u32>() {
                                Ok(id) => match sched.get_job(id) {
                                    Some(job) => format!("{}\n", job),
                                    None => format!("Error: Job #{} no encontrado\n", id),
                                },
                                Err(_) => "Error: El ID debe ser un número entero positivo\n".to_string(),
                            }
                        } else {
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
                        if let Some(id_str) = cmd.args.get(0) {
                            match id_str.parse::<u32>() {
                                Ok(id) => {
                                    let mut sched = scheduler.lock().unwrap();
                                    if sched.cancel_job(id) {
                                        // Guardar cambios después de cancelar
                                        guardar_scheduler(&sched).unwrap_or_else(|e| {
                                            error!("Error al guardar scheduler: {}", e);
                                        });
                                        format!("Job #{} cancelado correctamente\n", id)
                                    } else {
                                        format!("Error: No se pudo cancelar el Job #{}\n", id)
                                    }
                                }
                                Err(_) => "Error: El ID debe ser un número entero positivo\n".to_string(),
                            }
                        } else {
                            "Uso: cancel <id>\n".to_string()
                        }
                    }
                    // Comandos de ejecución (echo, sleep, ls, etc.)
                    _ => {
                        let (job_id, full_command) = {
                            let mut sched = scheduler.lock().unwrap();
                            let job = sched.add_job(cmd.program.clone(), cmd.args.clone());
                            let job_id = job.get_id();

                            // Guardar cambios después de agregar
                            guardar_scheduler(&sched).unwrap_or_else(|e| {
                                error!("Error al guardar scheduler: {}", e);
                            });

                            let full_command = if cmd.args.is_empty() {
                                cmd.program.clone()
                            } else {
                                format!("{} {}", cmd.program, cmd.args.join(" "))
                            };
                            (job_id, full_command)
                        };

                        // Tarea asíncrona en segundo plano sin bloquear el socket
                        let scheduler_clone = Arc::clone(&scheduler);
                        tokio::spawn(async move {
                            {
                                let mut sched = scheduler_clone.lock().unwrap();
                                sched.start_job(job_id);
                            }
                            let exec_result = Executor::run(&full_command).await;

                            let mut sched = scheduler_clone.lock().unwrap();
                            sched.complete_job(job_id, exec_result.exit_code);

                            // Guardar cambios después de completar
                            guardar_scheduler(&sched).unwrap_or_else(|e| {
                                error!("Error al guardar scheduler: {}", e);
                            });
                        });

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

