use speedyG::config::Config;
use speedyG::executor::Executor;
use speedyG::parser::parse;
use speedyG::persistence::{cargar_scheduler, guardar_scheduler};
use speedyG::scheduler::Scheduler;
use speedyG::state_machine::JobState;
use std::fs;
use std::sync::{Arc, Mutex, MutexGuard};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::UnixListener;
use tracing::{error, info, warn};
use speedyG::event_log::log_event;

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

        //  Ejecutar (mientras tanto, `status` mostrará Running)
        log_event(
            "./logs",
            "INFO",
            "JOB_STARTED",
            Some(job_id),
            &full_command,
        );

        info!("Job #{} ejecutando: {}", job_id, full_command);
        let exec_result = Executor::run(&full_command).await;

        //  Marcar como completado y guardar. Si lo cancelaron mientras corría,
        //    complete_job devuelve false y se conserva el estado Canceled.
        {
            let mut sched = lock(&scheduler);
            if sched.complete_job(job_id, exec_result.exit_code) {

                log_event(
                    "./logs",
                    "INFO",
                    "JOB_COMPLETED",
                    Some(job_id),
                    &format!("exit_code={}", exec_result.exit_code),
                );


                info!(
                    "Job #{} terminó con código {}",
                    job_id, exec_result.exit_code
                );

                persistir(&sched);

            } else {

                log_event(
                    "./logs",
                    "INFO",
                    "JOB_COMPLETED",
                    Some(job_id),
                    &format!("exit_code={}", exec_result.exit_code),
                );

                info!(
                    "Job #{} terminó pero ya estaba cancelado; se ignora el resultado",
                    job_id
                );
            }
        }
        //Despachar el siguiente trabajo si hay capacidad
        despachar(Arc::clone(&scheduler), max_current);
    });
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

        log_event(
    	    "./logs",
	    "INFO",
	    "SERVICE_RESTART",
	    None,
	    "Scheduler recuperado",
        );

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


                                        log_event(
        	                            "./logs",
	                                    "INFO",
	                                    "JOB_CANCELED",
    	                                    Some(id),
	                                    "Trabajo cancelado",
                                        );


                                        // Reflejar la cancelación en persistencia
                                        persistir(&sched);
                                        info!("Job #{} cancelado", id);
                                        format!("Job #{} cancelado correctamente\n", id)
                                    } else {

                                        log_event(
                                            "./logs",
                                            "WARN",
                                            "JOB_CANCEL_FAILED",
                                            Some(id),
                                            "Intento de cancelación fallido",
                                        );

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
                        let resultado = {
                            let mut sched = lock(&scheduler);

                            match sched.add_job(cmd.program.clone(), cmd.args.clone()){
                            	Ok(job)=> {
			    		let job_id = job.get_id();
                            		let full_command = job.get_command_line();

                                        log_event(
                                            "./logs",
                                            "INFO",
                                            "JOB_RECEIVED",
                                            Some(job_id),
                                            &full_command,
                                        );

                                        log_event(
                                            "./logs",
                                            "INFO",
                                            "JOB_QUEUED",
                                            Some(job_id),
                                            "Trabajo agregado a la cola",
                                        );


                            		// Guardar cambios después de agregar
                            		persistir(&sched);
                            		Ok((job_id, full_command))
			    	}
			        Err(error) => {

                                    log_event(
                                        "./logs",
                                        "WARN",
                                        "JOB_REJECTED",
                                        None,
                                        &error,
                                        );
                                    Err(error)
                                }


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
