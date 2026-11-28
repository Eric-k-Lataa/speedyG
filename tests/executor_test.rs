// tests/executor_test.rs

use speedyG::executor::{ExecutionResult, Executor};

// Helper interno para mantener limpios los tests con el nuevo flujo de 2 fases
async fn run_helper(cmd: &str) -> ExecutionResult {
    let (child, _pid) = Executor::spawn_cmd(cmd).expect("Fallo al hacer spawn del comando");
    Executor::wait_child(child, 1_000_000).await
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

#[tokio::test]
async fn conserva_salida_si_no_supera_el_limite() {
    let (child, _) = Executor::spawn_cmd("printf 'hola'").unwrap();
    let result = Executor::wait_child(child, 10).await;

    assert_eq!(result.stdout, "hola");
    assert!(!result.output_truncated);
}

#[tokio::test]
async fn trunca_salida_cuando_supera_el_limite() {
    let (child, _) = Executor::spawn_cmd("printf '1234567890'").unwrap();
    let result = Executor::wait_child(child, 5).await;

    assert_eq!(result.stdout.len(), 5);
    assert_eq!(result.stdout, "12345");
    assert!(result.output_truncated);
}

#[tokio::test]
async fn comparte_limite_entre_stdout_y_stderr() {
    let (child, _) = Executor::spawn_cmd("printf '123456'; printf '7890' >&2").unwrap();
    let result = Executor::wait_child(child, 8).await;

    assert_eq!(result.stdout.len() + result.stderr.len(), 8);
    assert!(result.output_truncated);
}
