#[cfg(test)]
use speedyG::parser::{is_reserved, parse, parse_with_limits, validate_command};

//pruebas comandos reservados
#[test]
fn reserved_command() {
    assert!(is_reserved("cancel"));
    assert!(is_reserved("status"));
    assert!(is_reserved("health"));
    assert!(is_reserved("help"));
}

//pruebas comando valido
#[test]
fn validate_status_with_id() {
    let args = vec!["5".to_string()];
    assert!(validate_command("status", &args).is_ok());
}
#[test]
fn validate_health_without_args() {
    let args = vec![];
    assert!(validate_command("health", &args).is_ok());
}
#[test]
fn validate_health_with_args() {
    let args = vec!["hola".to_string()];
    assert!(validate_command("health", &args).is_err());
}
#[test]
fn validate_status_with_invalid_id() {
    let args = vec!["hola".to_string()];
    assert!(validate_command("status", &args).is_err());
}

// Pruebas comandos que no son reservados
#[test]
fn parse_unreserved_command() {
    assert!(parse("comando_inexistente hola").is_ok());
}

#[test]
fn parse_unreserved_command_with_invalid_args() {
    assert!(parse("sleep abc").is_ok());
}

// Pruebas del comando list
#[test]
fn parse_list_command() {
    let result = parse("list").unwrap();

    assert_eq!(result.program, "status");
    assert!(result.args.is_empty());
}

#[test]
fn parse_list_with_args() {
    let result = parse("list 5");
    assert!(result.is_err());
}

// Pruebas de limites de argumentos

#[test]
fn parse_with_valid_limits() {
    assert!(parse_with_limits("echo hola mundo", 32, 256).is_ok());
}

#[test]
fn parse_exceeds_max_arguments() {
    let input = format!("echo {}", vec!["a"; 33].join(" "));
    assert!(parse_with_limits(&input, 32, 256).is_err());
}

#[test]
fn parse_exceeds_max_argument_bytes() {
    let argument = "a".repeat(257);
    let input = format!("echo {}", argument);
    assert!(parse_with_limits(&input, 32, 256).is_err());
}
