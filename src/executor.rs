// src/executor.rs
use tokio::process::Command;

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
    /// Ejecuta un comando en el sistema operativo mediante la shell /bin/sh
    pub async fn run(cmd: &str) -> ExecutionResult {
        let output = Command::new("sh").arg("-c").arg(cmd).output().await;

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
