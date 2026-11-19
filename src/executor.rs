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

        let pgid = Pid::from_raw(-(pid as i32));
        let _ = kill(pgid, Signal::SIGTERM);

        let deadline = Instant::now() + Duration::from_millis(grace_ms);
        while Instant::now() < deadline {
            if kill(pgid, None).is_err() {
                return;
            }
            tokio::time::sleep(Duration::from_millis(25)).await;
        }

        let _ = kill(pgid, Signal::SIGKILL);
    }

    /// Espera a que un proceso hijo termine y extrae su resultado
    pub async fn wait_child(child: Child) -> ExecutionResult {
        let output = child.wait_with_output().await;

        match output {
            Ok(out) => ExecutionResult {
                exit_code: out.status.code().unwrap_or(-1),
                success: out.status.success(),
                stdout: String::from_utf8_lossy(&out.stdout).to_string(),
                stderr: String::from_utf8_lossy(&out.stderr).to_string(),
            },
            Err(e) => ExecutionResult {
                exit_code: 1,
                success: false,
                stdout: String::new(),
                stderr: e.to_string(),
            },
        }
    }
}
