// tests/executor_test.rs

use speedyG::executor::{ExecutionResult, Executor};

#[tokio::test]
async fn test_successful_execution() {
    let result = Executor::run("echo 'hello speedyG'").await;

    assert!(result.success);
    assert_eq!(result.exit_code, 0);
    assert_eq!(result.stdout.trim(), "hello speedyG");
    assert!(result.stderr.is_empty());
}

#[tokio::test]
async fn test_failed_exit_code() {
    let result = Executor::run("exit 42").await;

    assert!(!result.success);
    assert_eq!(result.exit_code, 42);
    assert!(result.stdout.is_empty());
}

#[tokio::test]
async fn test_stderr_capture() {
    let result = Executor::run("echo 'fatal error' >&2").await;

    assert!(result.success); // El comando en sí se ejecutó correctamente (exit code 0)
    assert_eq!(result.exit_code, 0);
    assert_eq!(result.stderr.trim(), "fatal error");
}

#[tokio::test]
async fn test_command_with_pipes_and_subshells() {
    // Al usarse `sh -c`, debe soportar operadores de shell como pipes (|) y &&
    let result = Executor::run("echo 'linea 1\nlinea 2' | grep 'linea 2'").await;

    assert!(result.success);
    assert_eq!(result.exit_code, 0);
    assert_eq!(result.stdout.trim(), "linea 2");
}

#[tokio::test]
async fn test_non_existent_command() {
    let result = Executor::run("comando_inventado_xyz_123").await;

    assert!(!result.success);
    assert_ne!(result.exit_code, 0); // La shell retorna normalmente 127 para command not found
    assert!(result.stderr.contains("not found") || !result.stderr.is_empty());
}

#[tokio::test]
async fn test_multiline_output() {
    let result = Executor::run("printf 'a\\nb\\nc\\n'").await;

    assert!(result.success);
    assert_eq!(result.exit_code, 0);
    let lines: Vec<&str> = result.stdout.lines().collect();
    assert_eq!(lines, vec!["a", "b", "c"]);
}

#[tokio::test]
async fn test_empty_command_string() {
    let result = Executor::run("").await;

    assert!(result.success);
    assert_eq!(result.exit_code, 0);
    assert!(result.stdout.is_empty());
    assert!(result.stderr.is_empty());
}
