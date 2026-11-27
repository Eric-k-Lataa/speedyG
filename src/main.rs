use speedyG::config::Config;
use speedyG::executor::Executor;
use speedyG::parser::parse_with_limits;
use speedyG::persistence::{cargar_scheduler, guardar_scheduler};
use speedyG::protocol::parse_and_validate_header;
use speedyG::scheduler::{CancelOutcome, Scheduler};
use speedyG::state_machine::JobState;
use std::fs;
use std::net::{IpAddr, SocketAddr};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::Instant;
use tokio::io::{AsyncBufReadExt, AsyncRead, AsyncWrite, AsyncWriteExt, BufReader};
use tokio::net::{TcpListener, UnixListener};
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

fn peer_allowed(peer: &SocketAddr, allowlist: &[IpAddr]) -> bool {
    if allowlist.is_empty() {
        return true;
    }
    allowlist.contains(&peer.ip())
}

async fn read_message_line<R>(
    reader: &mut BufReader<R>,
    max_message_bytes: usize,
) -> Result<Option<String>, String>
where
    R: AsyncRead + Unpin,
{
    let mut raw = Vec::new();
    let mut chunk = Vec::new();

    loop {
        chunk.clear();
        let n = reader
            .read_until(b'\n', &mut chunk)
            .await
            .map_err(|e| format!("Error de lectura en el socket: {}", e))?;

        if n == 0 {
            if raw.is_empty() {
                return Ok(None);
            }
            break;
        }

        if raw.len() + chunk.len() > max_message_bytes {
            return Err("Error: el mensaje supera el tamanio maximo permitido.\n".to_string());
        }

        raw.extend_from_slice(&chunk);
        if raw.ends_with(b"\n") {
            break;
        }
    }

    let text = String::from_utf8(raw).map_err(|_| {
        "Error: mensaje rechazado por formato UTF-8 invalido. Envia texto valido.\n".to_string()
    })?;

    Ok(Some(text))
}

#[allow(clippy::too_many_arguments)]
async fn handle_client<S>(
    stream: S,
    scheduler: SharedScheduler,
    service_started_at: Instant,
    grace_ms: u64,
    max_current: usize,
    max_message_bytes: usize,
    max_arguments: usize,
    max_argument_bytes: usize,
) where
    S: AsyncRead + AsyncWrite + Unpin,
{
    let mut reader = BufReader::new(stream);

    loop {
        let raw_msg = match read_message_line(&mut reader, max_message_bytes).await {
            Ok(Some(msg)) => msg,
            Ok(None) => return,
            Err(err_msg) => {
                warn!("Solicitud rechazada: {}", err_msg.trim());
                let _ = reader.get_mut().write_all(err_msg.as_bytes()).await;
                let _ = reader.get_mut().shutdown().await;
                return;
            }
        };

        // Quitar solo el salto de línea delimitador del final del mensaje
        let without_newline = raw_msg
            .strip_suffix("\r\n")
            .or_else(|| raw_msg.strip_suffix('\n'))
            .unwrap_or(&raw_msg);
        let input_str = without_newline.trim();

        if input_str.is_empty() {
            warn!("Solicitud rechazada: mensaje vacio");
            let msg = "Error: mensaje vacio. Envia un comando valido.\n";
            if let Err(e) = reader.get_mut().write_all(msg.as_bytes()).await {
                error!("Error al escribir en el socket: {}", e);
                return;
            }
            continue;
        }

        if input_str.chars().any(|c| c.is_control()) {
            warn!("Solicitud rechazada: contiene caracteres de control");
            let msg = "Error: el mensaje contiene caracteres no permitidos.\n";
            if let Err(e) = reader.get_mut().write_all(msg.as_bytes()).await {
                error!("Error al escribir en el socket: {}", e);
                return;
            }
            continue;
        }

        let payload = match parse_and_validate_header(input_str) {
            Ok(cmd_line) => cmd_line,
            Err(err_msg) => {
                warn!("Solicitud rechazada por protocolo: {}", err_msg);
                let out = format!("Error de protocolo: {}\n", err_msg);
                if let Err(e) = reader.get_mut().write_all(out.as_bytes()).await {
                    error!("Error al escribir en el socket: {}", e);
                    return;
                }
                continue;
            }
        };

        let response = match parse_with_limits(payload.trim(), max_arguments, max_argument_bytes) {
            Ok(cmd) => match cmd.program.as_str() {
                "health" => {
                    let uptime_seconds = service_started_at.elapsed().as_secs();

                    let sched = lock(&scheduler);

                    let running = sched.filter_jobs_by_state("running").len();
                    let queued = sched.filter_jobs_by_state("queued").len();

                    format!(
                        "status=active\n\
                         service_version={}\n\
                         uptime_seconds={}\n\
                         running={}\n\
                         queued={}\n\
                         queue_capacity={}\n",
                         env!("CARGO_PKG_VERSION"),
                         uptime_seconds,
                         running,
                         queued,
                         sched.get_queue_cap()
    		     )
		},
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
                                let (outcome, pid_opt, respuesta) = {
                                    let mut sched = lock(&scheduler);
                                    let (outcome, pid) = sched.try_cancel(id);
                                    if outcome == CancelOutcome::Canceled {
                                        persistir(&sched);
                                    }
                                    (outcome, pid, mensaje_cancelacion(id, outcome))
                                };

                                if outcome == CancelOutcome::Canceled {
                                    if let Some(pid) = pid_opt {
                                        tokio::spawn(async move {
                                            Executor::kill_process_group(pid, grace_ms).await;
                                        });
                                    }
                                    info!("Job #{} cancelado", id);
                                    despachar(Arc::clone(&scheduler), max_current);
                                }
                                respuesta
                            }
                            Err(_) => "Error: El ID debe ser un número entero positivo\n".to_string(),
                        }
                    } else {
                        "Uso: cancel <id>\n".to_string()
                    }
                }
                _ => {
                    let resultado = {
                        let mut sched = lock(&scheduler);

                        match sched.add_job(cmd.program.clone(), cmd.args.clone()) {
                            Ok(job) => {
                                let job_id = job.get_id();
                                let full_command = job.get_command_line();
                                persistir(&sched);
                                Ok((job_id, full_command))
                            }
                            Err(error) => Err(error),
                        }
                    };

                    match resultado {
                        Ok((job_id, _full_command)) => {
                            despachar(Arc::clone(&scheduler), max_current);
                            format!("Job #{} encolado correctamente\n", job_id)
                        }
                        Err(error) => format!("{}\n", error),
                    }
                }
            },
            Err(err_msg) => {
                warn!("Solicitud rechazada: {}", err_msg);
                format!("Error de sintaxis: {}\n", err_msg)
            }
        };

        if let Err(e) = reader.get_mut().write_all(response.as_bytes()).await {
            error!("Error al escribir en el socket: {}", e);
            return;
        }
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
        /* if let Some(pid) = pid_opt {
            let mut sched = lock(&scheduler);
            sched.set_job_pid(job_id, pid);
        }
        */
        //Comente esta parte porque me estaba dando problemas con huerfanos, es remplazada por el siguiente bloque de codigo

        // Verificamos que sigue el job activo en la cola y registramos PID
        let sigue_activo = {
            let mut sched = lock(&scheduler);
            if let Some(pid) = pid_opt {
                sched.set_job_pid(job_id, pid)
            } else {
                sched
                    .pending_jobs()
                    .iter()
                    .any(|j| j.get_id() == job_id && matches!(j.get_state(), JobState::Running))
            }
        };

        if !sigue_activo {
            warn!(
                "Job #{} cancelado durante spawn; terminando proceso",
                job_id
            );
            if let Some(pid) = pid_opt {
                Executor::kill_process_group(pid, 100).await;
            }
            let _ = Executor::wait_child(child).await;
            return;
        }

        // Esperamos a que el proceso termine de forma asíncrona
        let exec_result = Executor::wait_child(child).await;

        // Marcar como completado y guardar.
        {
            let mut sched = lock(&scheduler);
            let ya_cancelado = sched
                .history_jobs()
                .iter()
                .any(|j| j.get_id() == job_id && matches!(j.get_state(), JobState::Canceled));

            if ya_cancelado {
                info!(
                    "Job #{} ya estaba cancelado; se ignora salida de wait_child",
                    job_id
                );
            } else if sched.complete_job(
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
                info!("Job #{} ya no estaba en cola activa al finalizar.", job_id);
            }
        }
        // Despachar el siguiente trabajo si hay capacidad
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

    // Inicializar tiempo de inicio
    let service_started_at = Instant::now();

    // Cargar configuración desde flags / variables de entorno / defaults
    let cfg = Config::from_env_and_args().unwrap_or_else(|err| {
        eprintln!("Error al cargar configuración: {}", err);
        std::process::exit(1);
    });

    info!(
        socket_path    = %cfg.socket_path,
        tcp_enabled    = %cfg.tcp_enabled,
        tcp_host       = %cfg.tcp_host,
        tcp_port       = %cfg.tcp_port,
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

    let tcp_listener = if cfg.tcp_enabled {
        let tcp = TcpListener::bind(cfg.tcp_addr()).await?;
        let real_addr = tcp.local_addr()?;
        info!("Demonio speedyG escuchando por TCP en {}", real_addr);
        Some(tcp)
    } else {
        info!("Listener TCP deshabilitado por configuración");
        None
    };

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

            tcp_res = async {
                match tcp_listener.as_ref() {
                    Some(tcp) => tcp.accept().await,
                    None => std::future::pending().await,
                }
            } => {
                let (stream, peer_addr) = match tcp_res {
                    Ok(res) => res,
                    Err(e) => {
                        error!("Error al aceptar conexión TCP: {}", e);
                        continue;
                    }
                };

                if !peer_allowed(&peer_addr, &cfg.tcp_allowlist) {
                    warn!("Conexión TCP rechazada por allow-list desde {}", peer_addr);
                    drop(stream);
                    continue;
                }

                if shutting_down.load(Ordering::SeqCst) {
                    let mut stream = stream;
                    let _ = stream
                        .write_all(b"Error: El demonio se esta apagando, no se aceptan nuevos comandos.\n")
                        .await;
                    let _ = stream.shutdown().await;
                    continue;
                }

                let scheduler = Arc::clone(&scheduler);
                let grace_ms = cfg.grace_ms;
                let max_current = cfg.max_current;
                let max_message_bytes = cfg.max_message_bytes;
                let max_arguments = cfg.max_arguments;
                let max_argument_bytes = cfg.max_argument_bytes;

                tokio::spawn(async move {
                    handle_client(
                        stream,
                        scheduler,
                        service_started_at,
                        grace_ms,
                        max_current,
                        max_message_bytes,
                        max_arguments,
                        max_argument_bytes,
                    )
                    .await;
                });
            }
            accept_res = listener.accept() => {
                let (stream, _) = match accept_res {
                    Ok(res) => res,
                    Err(e) => {
                        error!("Error al aceptar conexión del socket: {}", e);
                        continue;
                    }
                };

                // Si estamos en proceso de apagado, rechazamos nuevas solicitudes
                if shutting_down.load(Ordering::SeqCst) {
                    let mut stream = stream;
                    let _ = stream.write_all(b"Error: El demonio se esta apagando, no se aceptan nuevos comandos.\n").await;
                    let _ = stream.shutdown().await;
                    continue;
                }

                let scheduler = Arc::clone(&scheduler);
                let grace_ms = cfg.grace_ms;
                let max_current = cfg.max_current;
                let max_message_bytes = cfg.max_message_bytes;
                let max_arguments = cfg.max_arguments;
                let max_argument_bytes = cfg.max_argument_bytes;

                tokio::spawn(async move {
                    handle_client(
                        stream,
                        scheduler,
                        service_started_at,
                        grace_ms,
                        max_current,
                        max_message_bytes,
                        max_arguments,
                        max_argument_bytes,
                    )
                    .await;
                });
            }
        }
    }

    // --- FASE DE APAGADO LIMPIO (Graceful Shutdown) ---
    info!("Ejecutando rutina de limpieza de cierre...");

    let running_targets: Vec<(u32, Option<u32>)> = {
        let mut sched = lock(&scheduler);
        let running_ids: Vec<u32> = sched
            .pending_jobs()
            .iter()
            .filter(|j| matches!(j.get_state(), JobState::Running))
            .map(|j| j.get_id())
            .collect();

        let mut targets = Vec::new();
        for id in running_ids {
            info!(
                "Terminando job activo #{} debido al cierre del demonio...",
                id
            );
            let (outcome, pid_opt) = sched.try_cancel(id);
            if outcome == CancelOutcome::Canceled {
                targets.push((id, pid_opt));
            }
        }
        persistir(&sched);
        targets
    };

    let mut kill_handles = Vec::new();
    for (id, pid_opt) in running_targets {
        if let Some(pid) = pid_opt {
            let g_ms = cfg.grace_ms;
            kill_handles.push(tokio::spawn(async move {
                info!(
                    "Enviando señal de terminación a grupo de job #{} (PID {})",
                    id, pid
                );
                Executor::kill_process_group(pid, g_ms).await;
            }));
        }
    }
    for handle in kill_handles {
        let _ = handle.await;
    }

    // Margen breve para que las tareas de lanzar_job completen wait_child y cosechen hijos
    tokio::time::sleep(std::time::Duration::from_millis(100)).await;

    // 2. Eliminar el archivo del socket Unix
    drop(tcp_listener);
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
