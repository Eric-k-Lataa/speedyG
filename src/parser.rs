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
    let mut program = parts[0].to_string();

    //convertir list en status
    if program == "list" {
        if parts.len() > 1 {
            return Err(format!("{} no recibe argumentos", program));
        }
        program = "status".to_string();
    }

    let mut args = Vec::new();
    for arg in &parts[1..] {
        args.push(arg.to_string());
    }
    if is_reserved(&program) {
        validate_command(&program, &args)?;
    }
    Ok(ParsedCommand { program, args })
}

// Palabras reservadas
pub fn is_reserved(program: &str) -> bool {
    matches!(program, "status" | "health" | "cancel" | "help")
}

//validar argumentos de comando reservado
pub fn validate_command(program: &str, args: &[String]) -> Result<(), String> {
    match program {
        "status" => {
            if args.len() > 1 {
                return Err("status solo acepta un ID opcional".to_string());
            }
            if let Some(id_str) = args.first() {
                if id_str.parse::<u32>().is_err() {
                    return Err("El ID debe ser un entero".to_string());
                }
            }
        }
        "cancel" => {
            if args.len() != 1 {
                return Err(format!("{} requiere un ID", program));
            }
            if args[0].parse::<u32>().is_err() {
                return Err("El ID debe ser un entero".to_string());
            }
        }

        "health" | "help" if !args.is_empty() => {
            return Err(format!("{} no recibe argumentos", program));
        }
        "health" | "help" => {}
        _ => {}
    }
    Ok(())
}

//pruebas
#[cfg(test)]
mod tests {
    use super::*;

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
}
