// src/executor.rs
use std::process::Command;

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
    pub fn run(cmd: &str) -> ExecutionResult {
        let output = Command::new("sh").arg("-c").arg(cmd).output();

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

// Pruebas unitarias para validar executor.rs sin depender de la máquina de estados
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_successful_command() {
        let res = Executor::run("echo 'hola speedyG'");
        assert!(res.success);
        assert_eq!(res.exit_code, 0);
        assert!(res.stdout.contains("hola speedyG"));
    }

    #[test]
    fn test_failing_command() {
        let res = Executor::run("exit 42");
        assert!(!res.success);
        assert_eq!(res.exit_code, 42);
    }
}
