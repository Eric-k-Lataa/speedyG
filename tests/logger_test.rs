// tests/logger_test.rs
use speedyG::logger::EventLogger;
use std::fs;

#[test]
fn escribe_eventos_jsonl_con_correlacion_y_sin_secretos() {
    let dir = std::env::temp_dir().join(format!("speedyg_logger_test_{}", std::process::id()));
    let _ = fs::remove_dir_all(&dir);

    let logger = EventLogger::new(dir.to_str().unwrap()).expect("Debe crear EventLogger");
    let req_id = logger.next_request_id();

    logger.info(
        "request_received",
        Some(&req_id),
        None,
        "Solicitud recibida",
    );
    logger.info("job_queued", Some(&req_id), Some(7), "Trabajo #7 encolado");
    logger.info("job_started", None, Some(7), "Trabajo #7 iniciado");
    logger.warn(
        "job_escalation_sigkill",
        None,
        Some(7),
        "Trabajo #7 escalado a SIGKILL",
    );
    logger.info("job_finished", None, Some(7), "Trabajo #7 finalizado");

    let content = fs::read_to_string(logger.path()).expect("Debe leer events.jsonl");
    let lines: Vec<&str> = content.lines().collect();
    assert_eq!(lines.len(), 5);

    for line in &lines {
        let parsed: serde_json::Value =
            serde_json::from_str(line).expect("Cada línea debe ser JSON válido");
        assert!(parsed.get("timestamp").is_some());
        assert!(parsed.get("level").is_some());
        assert!(parsed.get("event").is_some());
        assert!(parsed.get("message").is_some());
    }

    assert!(content.contains(&req_id));
    assert!(content.contains("\"job_id\":7"));
    assert!(!content.contains("tcp_allowlist"));

    let _ = fs::remove_dir_all(&dir);
}
