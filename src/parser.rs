//lo que devuelve el parse
#[derive(Debug)]
pub struct ParsedCommand {
    pub program: String,
    pub args: Vec<String>,
}

//flujo del parser

pub fn parse(input: &str) -> Result<ParsedCommand, String> {
    let parts: Vec<&str> = input.split_whitespace().collect();
    if parts.is_empty() {
        return Err("El comando està vacio".to_string());
    }
    let program = parts[0].to_string();

    if !is_authorized(&program) {
        return Err("Comando no autorizado".to_string());
    }

    let mut args = Vec::new();
    for arg in &parts[1..] {
        args.push(arg.to_string());
    }

    validate_command(&program, &args)?;
    Ok(ParsedCommand { program, args })
}

//comandos autorizados
pub fn is_authorized(program: &str) -> bool {
    matches!(
        program,
        "status" | "echo" | "health" | "sleep" | "ls" | "cancel" | "help"
    )
}

//estructura del comando autorizado bien hecha
pub fn validate_command(program: &str, args: &[String]) -> Result<(), String> {
    match program {
        "status" | "cancel" => {
            if args.len() != 1 {
                return Err(format!("{} requiere un ID", program));
            }
            if args[0].parse::<u32>().is_err() {
                return Err("El ID debe ser un entero".to_string());
            }
        }
        "sleep" => {
            if args.len() != 1 {
                return Err(format!("{} requiere un argumento", program));
            }
        }

        "health" | "help" | "ls" => {
            if !args.is_empty() {
                return Err(format!("{} no recibe argumentos", program));
            }
        }
        "echo" => {}
        _ => {
            return Err("Comando no autorizado".to_string());
        }
    }
    Ok(())
}

//pruebas
#[cfg(test)]
mod tests {
    use super::*;
    //pruebas parser
    #[test]
    fn parse_sleep_command() {
        let result = parse("sleep 10").unwrap();
        assert_eq!(result.program, "sleep");
        assert_eq!(result.args, vec!["10"]);
    }

    #[test]
    fn parse_echo_command() {
        let result = parse("echo hola mundo").unwrap();
        assert_eq!(result.program, "echo");
        assert_eq!(result.args, vec!["hola", "mundo"]);
    }

    //prubas parser invalido
    #[test]
    fn parse_empty_command() {
        let result = parse("");
        assert!(result.is_err());
    }
    #[test]
    fn parse_whitespace_command() {
        let result = parse("     ");
        assert!(result.is_err());
    }
    //pruebas comandos autorizados/no autorizados
    #[test]
    fn authorized_command() {
        assert!(is_authorized("sleep"));
        assert!(is_authorized("ls"));
        assert!(is_authorized("echo"));
        assert!(is_authorized("health"));
        assert!(is_authorized("status"));
        assert!(is_authorized("cancel"));
        assert!(is_authorized("help"));
    }

    #[test]
    fn unauthorized_command() {
        assert!(!is_authorized("rm"));
    }

    #[test]
    fn parse_unauthorized_command() {
        let result = parse("rm archivo.txt");

        assert!(result.is_err());
    }

    //pruebas comando valido
    #[test]
    fn validate_status_with_id() {
        let args = vec!["5".to_string()];
        assert!(validate_command("status", &args).is_ok());
    }
    #[test]
    fn validate_status_without_id() {
        let args = vec![];
        assert!(validate_command("status", &args).is_err());
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
}
