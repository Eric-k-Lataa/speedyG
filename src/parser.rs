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

//valida los limites de argumentos y analiza el comando
pub fn parse_with_limits(
    input: &str,
    max_arguments: usize,
    max_argument_bytes: usize,
) -> Result<ParsedCommand, String> {
    let parts: Vec<&str> = input.split_whitespace().collect();

    if parts.is_empty() {
        return Err("El comando está vacío".to_string());
    }

    let args = &parts[1..];

    if args.len() > max_arguments {
        return Err(format!(
            "El comando supera el máximo de {} argumentos",
            max_arguments
        ));
    }

    for arg in args {
        if arg.len() > max_argument_bytes {
            return Err(format!(
                "El argumento '{}' supera el máximo de {} bytes",
                arg, max_argument_bytes
            ));
        }
    }

    parse(input)
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
                return Err("status solo acepta un argumento opcional (ID o estado)".to_string());
            }
            if let Some(arg) = args.first() {
                // Permitimos si es un u32 válido O si es una cadena de texto que representa un estado conocido
                let es_numero = arg.parse::<u32>().is_ok();
                let es_estado_valido = matches!(
                    arg.to_lowercase().as_str(),
                    "queued"
                        | "running"
                        | "succeeded"
                        | "failed"
                        | "canceled"
                        | "cancelled"
                        | "interrupted"
                );

                if !es_numero && !es_estado_valido {
                    return Err("El argumento de status debe ser un ID entero o un estado válido (queued, running, succeeded, failed, canceled, interrupted)".to_string());
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
