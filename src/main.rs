use speedyG::config::Config;
use speedyG::executor::Executor;
use speedyG::parser::parse;
use speedyG::persistence::{cargar_scheduler, guardar_scheduler};
use speedyG::scheduler::Scheduler;
use speedyG::state_machine::JobState;
use std::fs;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, MutexGuard};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::UnixListener;
use tokio::signal::unix::{signal, SignalKind};
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

        // Ejecutar y obtener pid
        info!("Job #{} ejecutando: {}", job_id, full_command);

        // 1. Lanzamos el proceso inmediatamente para obtener el PID
        let (child, pid_opt) = match Executor::spawn_cmd(&full_command) {
            Ok(res) => res,
            Err(e) => {
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

        // Ahora sí esperamos a que el proceso termine de forma asíncrona
        let exec_result = Executor::wait_child(child).await;

        // Marcar como completado y guardar.
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
        // Despachar el siguiente trabajo si hay capacidad
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
        persistir(&sched);
    }

    // despachar los trabajos recuperados respetando el limite de concurrencia
    despachar(Arc::clone(&scheduler), cfg.max_current);

    // Configurar escuchas de señales SIGINT (Ctrl+C) y SIGTERM
    let mut sigint = signal(SignalKind::interrupt())?;
    let mut sigterm = signal(SignalKind::terminate())?;

    // Bandera atómica para indicar que el demonio se está apagando y rechazar nuevos trabajos
    let shutting_down = Arc::new(AtomicBool::new(false));

    // Bucle principal selectivo entre aceptar conexiones o recibir señales de apagado
    loop {
        tokio::select! {
            _ = sigint.recv() => {
                info!("Recibida señal SIGINT (Ctrl+C). Iniciando apagado limpio...");
                shutting_down.store(true, Ordering::SeqCst);
                break;
            }
            _ = sigterm.recv() => {
                info!("Recibida señal SIGTERM. Iniciando apagado limpio...");
                shutting_down.store(true, Ordering::SeqCst);
                break;
            }
            accept_res = listener.accept() => {
                let (mut stream, _) = match accept_res {
                    Ok(res) => res,
                    Err(e) => {
                        error!("Error al aceptar conexión del socket: {}", e);
                        continue;
                    }
                };

                // Si estamos en proceso de apagado, rechazamos nuevas solicitudes
                if shutting_down.load(Ordering::SeqCst) {
                    let _ = stream.write_all(b"Error: El demonio se esta apagando, no se aceptan nuevos comandos.\n").await;
                    let _ = stream.shutdown().await;
                    continue;
                }

                let scheduler = Arc::clone(&scheduler);

                tokio::spawn(async move {
                    let mut buffer = [0; 1024];

                    let n = match stream.read(&mut buffer).await {
                        Ok(0) => return,
                        Ok(n) => n,
                        Err(e) => {
                            error!("Error al leer del socket: {}", e);
                            return;
                        }
                    };

                    let input = String::from_utf8_lossy(&buffer[..n]);
                    let input_str = input.trim();

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
                                    if let Ok(id) = arg.parse::<u32>() {
                                        match sched.get_job(id) {
                                            Some(job) => format!("{}\n", job),
                                            None => format!("Error: Job #{} no encontrado\n", id),
                                        }
                                    } else {
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
                                            let mut sched = lock(&scheduler);
                                            if sched.cancel_job(id) {
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
                            _ => {
                                let resultado = {
                                    let mut sched = lock(&scheduler);

                                    match sched.add_job(cmd.program.clone(), cmd.args.clone()){
                                        Ok(job)=> {
                                            let job_id = job.get_id();
                                            let full_command = job.get_command_line();
                                            persistir(&sched);
                                            Ok((job_id, full_command))
                                        }
                                        Err(error)=> Err(error),
                                    }
                                };

                                match resultado {
                                    Ok((job_id,_full_command))=> {
                                        despachar(Arc::clone(&scheduler), cfg.max_current);
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

                    if let Err(e) = stream.write_all(response.as_bytes()).await {
                        error!("Error al escribir en el socket: {}", e);
                    }
                });
            }
        }
    }

    // --- FASE DE APAGADO LIMPIO (Graceful Shutdown) ---
    info!("Ejecutando rutina de limpieza de cierre...");

    // 1. Matar todos los trabajos que sigan corriendo en el sistema operativo
    {
        let mut sched = lock(&scheduler);
        // Obtenemos los IDs de los jobs activos pendientes o en ejecución
        let running_ids: Vec<u32> = sched
            .pending_jobs()
            .iter()
            .filter(|j| matches!(j.get_state(), JobState::Running))
            .map(|j| j.get_id())
            .collect();

        for id in running_ids {
            info!(
                "Terminando job activo #{} debido al cierre del demonio...",
                id
            );
            sched.cancel_job(id);
        }
        persistir(&sched);
    }

    // 2. Eliminar el archivo del socket Unix
    if fs::metadata(&socket_path).is_ok() {
        if let Err(e) = fs::remove_file(&socket_path) {
            error!(
                "Error al eliminar el archivo de socket {}: {}",
                socket_path, e
            );
        } else {
            info!("Archivo de socket {} eliminado correctamente.", socket_path);
        }
    }

    info!("Demonio speedyG detenido de forma limpia.");
    Ok(())
}
