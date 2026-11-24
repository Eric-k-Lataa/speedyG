// src/executor.rs
use std::process::Stdio;
use tokio::process::{Child, Command};

/// Resultado de la ejecución de un subproceso
#[derive(Debug, PartialEq)]
pub struct ExecutionResult {
    pub exit_code: i32,
    pub success: bool,
    pub stdout: String,
    pub stderr: String,
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
    pub async fn kill_process_group(pid: u32, grace_ms: u64) {
        use nix::sys::signal::{kill, Signal};
        use nix::unistd::Pid;
        use std::time::{Duration, Instant};
        use tracing::{info, warn};

        if pid == 0 {
            return;
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
                return;
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
    }

    /// Espera a que un proceso hijo termine y extrae su resultado
    pub async fn wait_child(child: Child) -> ExecutionResult {
        use std::os::unix::process::ExitStatusExt;

        let output = child.wait_with_output().await;

        match output {
            Ok(out) => {
                let mut stderr = String::from_utf8_lossy(&out.stderr).to_string();
                let exit_code = match out.status.code() {
                    Some(code) => code,
                    None => {
                        if let Some(sig) = out.status.signal() {
                            let sig_name = nombre_senal(sig);
                            let diag = format!("Terminado por señal {} ({})", sig, sig_name);
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
                    success: out.status.success(),
                    stdout: String::from_utf8_lossy(&out.stdout).to_string(),
                    stderr,
                }
            }
            Err(e) => ExecutionResult {
                exit_code: 1,
                success: false,
                stdout: String::new(),
                stderr: e.to_string(),
            },
        }
    }
}
