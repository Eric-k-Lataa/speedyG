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
