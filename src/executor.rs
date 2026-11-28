// src/executor.rs
use std::process::Stdio;
use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Arc,
};
use tokio::io::AsyncReadExt;
use tokio::process::{Child, Command};

/// Resultado de la ejecución de un subproceso
#[derive(Debug, PartialEq)]
pub struct ExecutionResult {
    pub exit_code: i32,
    pub success: bool,
    pub stdout: String,
    pub stderr: String,
    pub output_truncated: bool,
}

#[cfg(unix)]
fn nombre_senal(sig: i32) -> String {
    match sig {
        1 => "SIGHUP".to_string(),
        2 => "SIGINT".to_string(),
        3 => "SIGQUIT".to_string(),
        6 => "SIGABRT".to_string(),
        9 => "SIGKILL".to_string(),
        13 => "SIGPIPE".to_string(),
        14 => "SIGALRM".to_string(),
        15 => "SIGTERM".to_string(),
        _ => format!("SIG{}", sig),
    }
}

// Lee la salida de un proceso por bloques, conservando solamente los bytes permitidos por el límite compartido entre stdout y stderr
async fn read_limited<R>(
    mut reader: R,
    max_bytes: usize,
    total_bytes: Arc<AtomicUsize>,
    truncated: Arc<std::sync::atomic::AtomicBool>,
) -> Vec<u8>
where
    R: tokio::io::AsyncRead + Unpin,
{
    let mut output = Vec::new();
    let mut buffer = [0u8; 8192];

    loop {
        match reader.read(&mut buffer).await {
            Ok(0) | Err(_) => break,
            Ok(n) => {
                let previous = total_bytes
                    .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |current| {
                        Some(current.saturating_add(n))
                    })
                    .unwrap_or_else(|current| current);

                let available = max_bytes.saturating_sub(previous);
                let keep = n.min(available);

                output.extend_from_slice(&buffer[..keep]);

                if keep < n {
                    truncated.store(true, Ordering::Relaxed);
                }
            }
        }
    }

    output
}

pub struct Executor;

impl Executor {
    /// Lanza el comando y devuelve inmediatamente el proceso hijo (Child) y su PID
    pub fn spawn_cmd(cmd: &str) -> Result<(Child, Option<u32>), String> {
        let mut command = Command::new("sh");
        command.arg("-c").arg(cmd);

        command.stdout(Stdio::piped());
        command.stderr(Stdio::piped());

        #[cfg(unix)]
        {
            //use std::os::unix::process::CommandExt;
            command.process_group(0);
        }

        let child = command.spawn().map_err(|e| e.to_string())?;
        let pid = child.id();
        Ok((child, pid))
    }

    #[cfg(unix)]
    pub async fn kill_process_group(pid: u32, grace_ms: u64) -> bool {
        use nix::sys::signal::{kill, Signal};
        use nix::unistd::Pid;
        use std::time::{Duration, Instant};
        use tracing::{info, warn};

        if pid == 0 {
            return false;
        }

        let pgid = Pid::from_raw(-(pid as i32));
        info!(
            pid = pid,
            pgid = %pgid,
            grace_ms = grace_ms,
            "Enviando SIGTERM al grupo de procesos"
        );
        let _ = kill(pgid, Signal::SIGTERM);

        let deadline = Instant::now() + Duration::from_millis(grace_ms);
        while Instant::now() < deadline {
            if kill(pgid, None).is_err() {
                info!(pid = pid, pgid = %pgid, "Grupo de procesos terminado tras SIGTERM");
                return false;
            }
            tokio::time::sleep(Duration::from_millis(25)).await;
        }

        warn!(
            pid = pid,
            pgid = %pgid,
            grace_ms = grace_ms,
            "Venció el tiempo de gracia; escalando a SIGKILL en el grupo de procesos"
        );

        let _ = kill(pgid, Signal::SIGKILL);
        true
    }

    /// Espera a que un proceso hijo termine y extrae su resultado
    pub async fn wait_child(mut child: Child, max_output_bytes: usize) -> ExecutionResult {
        use std::os::unix::process::ExitStatusExt;

        let stdout_reader = child.stdout.take().unwrap();
        let stderr_reader = child.stderr.take().unwrap();

        let total_bytes = Arc::new(AtomicUsize::new(0));
        let truncated = Arc::new(std::sync::atomic::AtomicBool::new(false));

        let (stdout, stderr, status) = tokio::join!(
            read_limited(
                stdout_reader,
                max_output_bytes,
                total_bytes.clone(),
                truncated.clone()
            ),
            read_limited(
                stderr_reader,
                max_output_bytes,
                total_bytes.clone(),
                truncated.clone()
            ),
            child.wait(),
        );

        let mut stderr = String::from_utf8_lossy(&stderr).to_string();

        match status {
            Ok(status) => {
                let exit_code = match status.code() {
                    Some(code) => code,
                    None => {
                        if let Some(sig) = status.signal() {
                            let diag =
                                format!("Terminado por señal {} ({})", sig, nombre_senal(sig));
                            if stderr.is_empty() {
                                stderr = diag;
                            } else {
                                stderr.push_str(&format!("\n{}", diag));
                            }
                            128 + sig
                        } else {
                            -1
                        }
                    }
                };

                ExecutionResult {
                    exit_code,
                    success: status.success(),
                    stdout: String::from_utf8_lossy(&stdout).to_string(),
                    stderr,
                    output_truncated: truncated.load(Ordering::Relaxed),
                }
            }
            Err(e) => ExecutionResult {
                exit_code: 1,
                success: false,
                stdout: String::new(),
                stderr: e.to_string(),
                output_truncated: truncated.load(Ordering::Relaxed),
            },
        }
    }
}
