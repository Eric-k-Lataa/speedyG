# Registro de uso de IA

## Objetivo
Obtener una idea de estructura para poder comenzar a implementar la maquina de estados en Rust.

## Pregunta realizada a la IA

> "Conociendo la lista de comandos a reconocer, como me recomiendas hacer el parser"

## Resultado recibido 

``` rust

En Rust podrías crear algo así:

pub enum Command {
    Submit {
        program: String,
        args: Vec<String>,
    },
    Status {
        id: u32,
    },
    List,
    Cancel {
        id: u32,
    },
    Help,
    Health,
}

Después haces una función parse

Por ejemplo:

pub fn parse(input: &str) -> Result<Command, String> {
    let parts: Vec<&str> = input.split_whitespace().collect();

    if parts.is_empty() {
        return Err("Comando vacío".to_string());
    }

    match parts[0] {
        "submit" => {
            if parts.len() < 2 {
                return Err("Falta el comando a ejecutar".to_string());
            }

            let program = parts[1].to_string();

            let args = parts[2..]
                .iter()
                .map(|arg| arg.to_string())
                .collect();

            Ok(Command::Submit { program, args })
        }

        "status" => {
            if parts.len() != 2 {
                return Err("Uso: status <id>".to_string());
            }

            let id = parts[1]
                .parse::<u32>()
                .map_err(|_| "El ID debe ser un número".to_string())?;

            Ok(Command::Status { id })
        }

        "list" => {
            if parts.len() != 1 {
                return Err("Uso: list".to_string());
            }

            Ok(Command::List)
        }

        "cancel" => {
            if parts.len() != 2 {
                return Err("Uso: cancel <id>".to_string());
            }

            let id = parts[1]
                .parse::<u32>()
                .map_err(|_| "El ID debe ser un número".to_string())?;

            Ok(Command::Cancel { id })
        }

        "help" => Ok(Command::Help),

        "health" => Ok(Command::Health),

        _ => Err("Comando desconocido".to_string()),
    }
}


```

## Revisión realizada

Se revisó la propuesta y se comparó con los requerimientos del parser del proyecto así como la idea que tiene el equipo sobre los comandos a usar. Aunque el código podía como un parser básico, la estructura propuesta no se ajustaba a la forma en que se necesitaba manejar los comandos autorizados  su validación.

## Decisión

**Rechazada**

La propuesta fue rechaza como implementación para el proyecto, ya que no era generico a como buscabamos que lo fuera. Esto hacia que mezclara el reconocimiento del comando con la estructura específica de cada uno. A pesar de ello, se usó de inspiración para implementar el parser. 

Para el proyecto se necesitó separar la identificación del programa y sus argumentos, la comprobación de si el comando estaba autorizado y la validación de los argumentos de cada comando.

## Prueba agregada
Se realizaron pruebas para comprobar el manejo de comandos vacíos, comandos no autorizados y comandos autorizados con argumentos válidos e inválidos.

## Aprendizaje

Se comprendió que una propuesta de IA puede ser funcional como ejemplo general, pero no necesariamente adaptarse a los requerimientos específicos del proyecto. También se identifico la importancia de separar responsabilidades a la hora de crear el parser.


