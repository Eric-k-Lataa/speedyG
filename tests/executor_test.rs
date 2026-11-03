// tests/executor_test.rs

use speedyG::executor::{ExecutionResult, Executor};

// Helper interno para mantener limpios los tests con el nuevo flujo de 2 fases
async fn run_helper(cmd: &str) -> ExecutionResult {
    let (child, _pid) = Executor::spawn_cmd(cmd).expect("Fallo al hacer spawn del comando");
    Executor::wait_child(child).await
}

#[tokio::test]
async fn test_successful_execution() {
    let result = run_helper("echo 'hello speedyG'").await;

    assert!(result.success);
    assert_eq!(result.exit_code, 0);
    assert_eq!(result.stdout.trim(), "hello speedyG");
    assert!(result.stderr.is_empty());
}

#[tokio::test]
async fn test_failed_exit_code() {
    let result = run_helper("exit 42").await;

    assert!(!result.success);
    assert_eq!(result.exit_code, 42);
    assert!(result.stdout.is_empty());
}

#[tokio::test]
async fn test_stderr_capture() {
    let result = run_helper("echo 'fatal error' >&2").await;

    assert!(result.success); // El comando en sí se ejecutó correctamente (exit code 0)
    assert_eq!(result.exit_code, 0);
    assert_eq!(result.stderr.trim(), "fatal error");
}

#[tokio::test]
async fn test_command_with_pipes_and_subshells() {
    // Al usarse `sh -c`, debe soportar operadores de shell como pipes (|) y &&
    let result = run_helper("echo 'linea 1\nlinea 2' | grep 'linea 2'").await;

    assert!(result.success);
    assert_eq!(result.exit_code, 0);
    assert_eq!(result.stdout.trim(), "linea 2");
}

#[tokio::test]
async fn test_non_existent_command() {
    let result = run_helper("comando_inventado_xyz_123").await;

    assert!(!result.success);
    assert_ne!(result.exit_code, 0); // La shell retorna normalmente 127 para command not found
    assert!(result.stderr.contains("not found") || !result.stderr.is_empty());
}

#[tokio::test]
async fn test_multiline_output() {
    let result = run_helper("printf 'a\\nb\\nc\\n'").await;

    assert!(result.success);
    assert_eq!(result.exit_code, 0);
    let lines: Vec<&str> = result.stdout.lines().collect();
    assert_eq!(lines, vec!["a", "b", "c"]);
}

#[tokio::test]
async fn test_empty_command_string() {
    let result = run_helper("").await;

    assert!(result.success);
    assert_eq!(result.exit_code, 0);
    assert!(result.stdout.is_empty());
    assert!(result.stderr.is_empty());
}
