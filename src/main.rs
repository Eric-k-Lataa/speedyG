use speedyG::config::Config;
use speedyG::executor::Executor;
use speedyG::parser::parse;
use speedyG::persistence::{cargar_scheduler, guardar_scheduler};
use speedyG::scheduler::{CancelOutcome, Scheduler};
use speedyG::state_machine::JobState;
use std::fs;
//use std::os::unix::process::ExitStatusExt;
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

fn lanzar_job(scheduler: SharedScheduler, job_id: u32, full_command: String, max_current: usize) {
    tokio::spawn(async move {
        // Verificar que el Job siga en estado Running antes de ejecutarlo
        {
            let sched = lock(&scheduler);

            if !matches!(
                sched.get_job(job_id).map(|job| job.get_state()),
                Some(JobState::Running)
            ) {
                warn!(
                    "Job #{} ya no está en ejecución (¿cancelado?); no se ejecuta",
                    job_id
                );
                return;
            }
        }

        //  Ejecutar y obtener pid
        info!("Job #{} ejecutando: {}", job_id, full_command);

        // 1. Lanzamos el proceso inmediatamente para obtener el PID
        let (child, pid_opt) = match Executor::spawn_cmd(&full_command) {
            Ok(res) => res,
            Err(e) => {
                // Manejo de error de inicio...
                let mut sched = lock(&scheduler);
                sched.complete_job(job_id, 1, "".into(), e);
                return;
            }
        };

        // 2. REGISTRAMOS EL PID EN EL SCHEDULER AL INSTANTE (Antes de esperar)
        if let Some(pid) = pid_opt {
            let mut sched = lock(&scheduler);
            sched.set_job_pid(job_id, pid);
        }

        //Ahora si esperamos a que el proceso termine de forma asíncrona
        let exec_result = Executor::wait_child(child).await;

        //  Marcar como completado y guardar. Si lo cancelaron mientras corría,
        //    complete_job devuelve false y se conserva el estado Canceled.
        {
            let mut sched = lock(&scheduler);
            if sched.complete_job(
                job_id,
                exec_result.exit_code,
                exec_result.stdout,
                exec_result.stderr,
            ) {
                info!(
                    "Job #{} terminó con código {}",
                    job_id, exec_result.exit_code
                );
                persistir(&sched);
            } else {
                info!("Job #{} cancelado en Running.", job_id);
            }
        }
        //Despachar el siguiente trabajo si hay capacidad
        despachar(Arc::clone(&scheduler), max_current);
    });
}

/// Mensaje al cliente según el resultado de `cancel` (operación, causa y acción: RNF-21)
fn mensaje_cancelacion(id: u32, outcome: CancelOutcome) -> String {
    match outcome {
        CancelOutcome::Canceled => format!("Job #{} cancelado correctamente\n", id),
        CancelOutcome::AlreadyCanceled => format!(
            "Job #{} ya estaba cancelado; no se realizó una nueva cancelación\n",
            id
        ),
        CancelOutcome::AlreadyFinished(estado) => format!(
            "Error: No se puede cancelar el Job #{}: ya está terminado (estado: {:?}). Consulta 'status {}' para ver su resultado\n",
            id, estado, id
        ),
        CancelOutcome::NotFound => format!(
            "Error: No se puede cancelar el Job #{}: no encontrado (no existe un trabajo con ese ID). Usa 'status' para ver los IDs disponibles\n",
            id
        ),
    }
}

fn despachar(scheduler: SharedScheduler, max_current: usize) {
    loop {
        let siguiente = {
            let mut sched = lock(&scheduler);
            let siguiente = sched.start_next_job(max_current);

            if siguiente.is_some() {
                persistir(&sched);
            }
            siguiente
        };
        match siguiente {
            Some((job_id, full_command)) => {
                lanzar_job(Arc::clone(&scheduler), job_id, full_command, max_current);
            }
            None => break,
        }
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Inicializar el logger
    tracing_subscriber::fmt::init();

    // Cargar configuración desde flags / variables de entorno / defaults
    let cfg = Config::from_env_and_args().unwrap_or_else(|err| {
        eprintln!("Error al cargar configuración: {}", err);
        std::process::exit(1);
    });

    info!(
        socket_path    = %cfg.socket_path,
        queue_cap      = %cfg.queue_cap,
        max_current    = %cfg.max_current,
        grace_ms       = %cfg.grace_ms,
        data_dir       = %cfg.data_dir,
        "Configuración cargada"
    );

    let socket_path = cfg.socket_path.clone();

    // Crear el directorio de datos si no existe
    if let Err(e) = fs::create_dir_all(&cfg.data_dir) {
        error!("Error al crear directorio de datos {}: {}", cfg.data_dir, e);
    }

    // Eliminar el socket si quedó de una ejecución previa
    if fs::metadata(&socket_path).is_ok() {
        fs::remove_file(&socket_path)?;
    }

    let listener = UnixListener::bind(&socket_path)?;
    info!("Demonio speedyG escuchando en {}", socket_path);

    // Scheduler compartido entre las conexiones. Se carga de SQLite/JSON.
    let mut sched = cargar_scheduler();
    sched.set_queue_cap(cfg.queue_cap);

    let scheduler: SharedScheduler = Arc::new(Mutex::new(sched));

    // Recuperación tras reinicio: Running -> Interrupted; Queued, permanece en cola.
    {
        let mut sched = lock(&scheduler);
        sched.recuperar_tras_reinicio();
        persistir(&sched);
    }

    // despachar los trabajos recuperados respetando el limite de concurrencia
    despachar(Arc::clone(&scheduler), cfg.max_current);
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
                            let arg = id_str;
                            // Caso: status <id>
                            if let Ok(id) = arg.parse::<u32>() {
                                match sched.get_job(id) {
                                    Some(job) => format!("{}\n", job),
                                    None => format!("Error: Job #{} no encontrado\n", id),
                                }
                            } else {
                                // Filtrar por estado
                                let filtrados = sched.filter_jobs_by_state(arg);
                                if filtrados.is_empty() {
                                    format!("No hay jobs con el estado '{}'.\n", arg)
                                } else {
                                    let mut out = format!("--- Jobs con estado '{}' ---\n", arg);
                                    for job in filtrados {
                                        out.push_str(&format!("{}\n", job.summary_string()));
                                    }
                                    out
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
                                        out.push_str(&format!("{}\n", job.summary_string()));
                                    }
                                }
                                if !history.is_empty() {
                                    out.push_str("--- Historial ---\n");
                                    for job in history {
                                        out.push_str(&format!("{}\n", job.summary_string()));
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
                                    let (outcome, respuesta) = {
                                        let mut sched = lock(&scheduler);
                                        let outcome = sched.try_cancel(id);
                                        if outcome == CancelOutcome::Canceled {
                                            // Reflejar la cancelación en persistencia
                                            persistir(&sched);
                                        }
                                        (outcome, mensaje_cancelacion(id, outcome))
                                    };
                                    if outcome == CancelOutcome::Canceled {
                                        info!("Job #{} cancelado", id);
                                        // La ranura quedó libre: avanzar la cola
                                        despachar(Arc::clone(&scheduler), cfg.max_current);
                                    }
                                    respuesta
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
                        let resultado = {
                            let mut sched = lock(&scheduler);

                            match sched.add_job(cmd.program.clone(), cmd.args.clone()){
                            	Ok(job)=> {
			    		let job_id = job.get_id();
                            		let full_command = job.get_command_line();

                            		// Guardar cambios después de agregar
                            		persistir(&sched);
                            		Ok((job_id, full_command))
			    	}
			        Err(error)=> Err(error),
			    }
                        };

			match resultado {
			   Ok((job_id,_full_command))=> {
                               // despachar trabajos respetando el limite de concurrencia
                               despachar(Arc::clone(&scheduler), cfg.max_current);

                               // Respuesta inmediata al cliente CLI
                               format!("Job #{} encolado correctamente\n", job_id)
                           }
		           Err(error)=> {
			       format!("{}\n",error)
		           }
		        }
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
