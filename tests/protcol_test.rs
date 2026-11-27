// tests/protocol_test.rs
use speedyG::protocol::{
    attach_version_header, parse_and_validate_header, ProtocolVersion, SERVER_MAJOR, SERVER_MINOR,
};

#[test]
fn attaches_current_version_header_to_payload() {
    let framed = attach_version_header("health");
    assert_eq!(
        framed,
        format!("v={}.{}|health", SERVER_MAJOR, SERVER_MINOR)
    );
}

#[test]
fn accepts_exact_current_version_and_extracts_payload() {
    let framed = attach_version_header("status 1");
    let payload = parse_and_validate_header(&framed).expect("debe aceptar la versión actual");
    assert_eq!(payload, "status 1");
}

#[test]
fn accepts_compatible_earlier_minor_version() {
    // Si SERVER_MINOR > 0, probamos una menor anterior (ej. 1.0 en servidor 1.2).
    // Si SERVER_MINOR == 0, probamos 1.0 como límite inferior válido.
    let older_minor = SERVER_MINOR.saturating_sub(1);
    let line = format!("v={}.{}|sleep 2", SERVER_MAJOR, older_minor);
    let payload = parse_and_validate_header(&line).expect("debe aceptar versión menor compatible");
    assert_eq!(payload, "sleep 2");
}

#[test]
fn rejects_incompatible_major_version_with_supported_info() {
    let incompatible_major = SERVER_MAJOR + 1;
    let line = format!("v={}.0|health", incompatible_major);
    let err = parse_and_validate_header(&line).expect_err("debe rechazar versión mayor distinta");

    assert!(
        err.contains(&SERVER_MAJOR.to_string()),
        "el error debe indicar la versión soportada; mensaje: {}",
        err
    );
}

#[test]
fn rejects_newer_unsupported_minor_version() {
    let newer_minor = SERVER_MINOR + 1;
    let line = format!("v={}.{}|health", SERVER_MAJOR, newer_minor);
    let err = parse_and_validate_header(&line).expect_err("debe rechazar versión menor superior");

    assert!(
        err.contains(&format!("{}.{}", SERVER_MAJOR, SERVER_MINOR)),
        "el error debe indicar el rango/versión soportada; mensaje: {}",
        err
    );
}

#[test]
fn rejects_malformed_or_missing_header() {
    assert!(parse_and_validate_header("health").is_err());
    assert!(parse_and_validate_header("1.0|health").is_err());
    assert!(parse_and_validate_header("v=abc|health").is_err());
    assert_eq!(
        ProtocolVersion::parse("v1").unwrap_err(),
        "Versión incompatible 'v1': se esperaba formato <major>.<minor>"
    );
}
