// src/bin/speedyg.rs
// Cliente CLI del demonio speedyG (A3-07).
// Precedencia de transporte:
//   1. Flags TCP: --host <ip/host> y/o --port <puerto>
//   2. Variables de entorno TCP: SPEEDYG_HOST y/o SPEEDYG_PORT
//   3. Transporte local Unix Socket: --socket <ruta> -> SPEEDYG_SOCKET -> /tmp/speedyg.sock
//
// Códigos de salida (RF-17 / A3-07):
//   0: Operación exitosa
//   2: Error de uso o argumentos inválidos en CLI
//   3: Error de conexión, timeout o demonio inalcanzable
//   4: Solicitud rechazada por el servidor (sintaxis, cola llena, job inexistente, etc.)
//   5: Versión de protocolo incompatible

use speedyG::protocol::attach_version_header;
use std::env;
use std::process;
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpStream, UnixStream};
use tokio::time::timeout;

const DEFAULT_TCP_HOST: &str = "127.0.0.1";
const DEFAULT_TCP_PORT: u16 = 7878;
const DEFAULT_SOCKET_PATH: &str = "/tmp/speedyg.sock";
const DEFAULT_TIMEOUT_MS: u64 = 5_000;

const EXIT_OK: i32 = 0;
const EXIT_USAGE: i32 = 2;
const EXIT_CONNECTION: i32 = 3;
const EXIT_SERVER_REJECTED: i32 = 4;
const EXIT_PROTOCOL_VERSION: i32 = 5;

enum TransportConfig {
    Tcp { host: String, port: u16 },
    Unix { socket_path: String },
}

fn print_help() {
    println!(
        "speedyg - Cliente CLI de JobRunner (local y remoto)\n\n\
         USO:\n  \
           speedyg [OPCIONES DE CONEXIÓN] <COMANDO> [ARGUMENTOS...]\n\n\
         OPCIONES DE RED Y CONEXIÓN (Precedencia: CLI > Entorno > Local):\n  \
           --host <ip_o_host>     Dirección del servidor TCP (env: SPEEDYG_HOST, default: 127.0.0.1)\n  \
           --port <puerto>        Puerto TCP del servidor (env: SPEEDYG_PORT, default: 7878)\n  \
           --socket <ruta>        Ruta del Unix Socket local (env: SPEEDYG_SOCKET, default: /tmp/speedyg.sock)\n  \
           --timeout-ms <ms>      Timeout de conexión y lectura en ms (env: SPEEDYG_TIMEOUT_MS, default: 5000)\n  \
           -h, --help             Muestra esta ayuda detallada\n\n\
         COMANDOS:\n  \
           <programa> [args...]   Encola un comando o programa para ejecución\n  \
           status [id | estado]   Consulta todos los jobs, uno por ID o filtra por estado\n  \
           list                   Alias de 'status' (lista todos los jobs)\n  \
           cancel <id>            Solicita cancelar un job en cola o ejecución\n  \
           health                 Muestra el estado de salud y capacidad del servicio\n  \
           help                   Muestra esta ayuda\n\n\
         CÓDIGOS DE SALIDA:\n  \
           0  Éxito\n  \
           2  Error de uso o parámetros inválidos\n  \
           3  Error de conexión, timeout o acceso rechazado por red\n  \
           4  Solicitud rechazada por el servidor (error de sintaxis, cola llena, job no encontrado)\n  \
           5  Versión de protocolo incompatible"
    );
}

fn parse_port(raw: &str, source: &str) -> u16 {
    raw.parse::<u16>().unwrap_or_else(|_| {
        eprintln!(
            "Error de uso: Puerto inválido '{}' en {}. Acción sugerida: indique un entero entre 1 y 65535.",
            raw, source
        );
        process::exit(EXIT_USAGE);
    })
}

fn parse_timeout(raw: &str, source: &str) -> u64 {
    match raw.parse::<u64>() {
        Ok(ms) if ms > 0 => ms,
        _ => {
            eprintln!(
                "Error de uso: Timeout inválido '{}' en {}. Acción sugerida: indique milisegundos > 0.",
                raw, source
            );
            process::exit(EXIT_USAGE);
        }
    }
}

fn resolve_cli_config(raw_args: &[String]) -> (TransportConfig, Duration, Vec<String>) {
    let mut socket_path =
        env::var("SPEEDYG_SOCKET").unwrap_or_else(|_| DEFAULT_SOCKET_PATH.to_string());

    let env_host = env::var("SPEEDYG_HOST")
        .ok()
        .filter(|v| !v.trim().is_empty());
    let env_port = env::var("SPEEDYG_PORT")
        .ok()
        .filter(|v| !v.trim().is_empty())
        .map(|v| parse_port(&v, "SPEEDYG_PORT"));

    let mut timeout_ms = env::var("SPEEDYG_TIMEOUT_MS")
        .ok()
        .filter(|v| !v.trim().is_empty())
        .map(|v| parse_timeout(&v, "SPEEDYG_TIMEOUT_MS"))
        .unwrap_or(DEFAULT_TIMEOUT_MS);

    let mut cli_host: Option<String> = None;
    let mut cli_port: Option<u16> = None;
    let mut cli_socket_explicit = false;
    let mut command_args: Vec<String> = Vec::new();

    let mut i = 0;
    while i < raw_args.len() {
        match raw_args[i].as_str() {
            "-h" | "--help" => {
                print_help();
                process::exit(EXIT_OK);
            }
            "--socket" => {
                if let Some(val) = raw_args.get(i + 1) {
                    socket_path = val.clone();
                    cli_socket_explicit = true;
                    i += 2;
                } else {
                    eprintln!("Error de uso: Falta el valor para --socket. Acción sugerida: especifique una ruta válida.");
                    process::exit(EXIT_USAGE);
                }
            }
            "--host" => {
                if let Some(val) = raw_args.get(i + 1) {
                    cli_host = Some(val.clone());
                    i += 2;
                } else {
                    eprintln!("Error de uso: Falta el valor para --host. Acción sugerida: especifique una IP o hostname.");
                    process::exit(EXIT_USAGE);
                }
            }
            "--port" => {
                if let Some(val) = raw_args.get(i + 1) {
                    cli_port = Some(parse_port(val, "--port"));
                    i += 2;
                } else {
                    eprintln!("Error de uso: Falta el valor para --port. Acción sugerida: especifique un puerto (ej. 7878).");
                    process::exit(EXIT_USAGE);
                }
            }
            "--timeout-ms" => {
                if let Some(val) = raw_args.get(i + 1) {
                    timeout_ms = parse_timeout(val, "--timeout-ms");
                    i += 2;
                } else {
                    eprintln!("Error de uso: Falta el valor para --timeout-ms. Acción sugerida: especifique milisegundos (ej. 5000).");
                    process::exit(EXIT_USAGE);
                }
            }
            _ => {
                command_args.push(raw_args[i].clone());
                i += 1;
            }
        }
    }

    if command_args.len() == 1 && command_args[0] == "help" {
        print_help();
        process::exit(EXIT_OK);
    }

    let use_tcp = if cli_host.is_some() || cli_port.is_some() {
        true
    } else if cli_socket_explicit {
        false
    } else {
        env_host.is_some() || env_port.is_some()
    };

    let transport = if use_tcp {
        let host = cli_host
            .or(env_host)
            .unwrap_or_else(|| DEFAULT_TCP_HOST.to_string());
        let port = cli_port.or(env_port).unwrap_or(DEFAULT_TCP_PORT);
        TransportConfig::Tcp { host, port }
    } else {
        TransportConfig::Unix { socket_path }
    };

    (transport, Duration::from_millis(timeout_ms), command_args)
}

async fn send_and_receive<S>(
    mut stream: S,
    wire_message: &str,
    io_timeout: Duration,
) -> Result<String, (i32, String)>
where
    S: AsyncReadExt + AsyncWriteExt + Unpin,
{
    match timeout(io_timeout, stream.write_all(wire_message.as_bytes())).await {
        Ok(Ok(())) => {}
        Ok(Err(e)) => {
            return Err((
                EXIT_CONNECTION,
                format!(
                    "Error de conexión al enviar datos al demonio ({}). Acción sugerida: verifique que el servicio siga activo.",
                    e
                ),
            ));
        }
        Err(_) => {
            return Err((
                EXIT_CONNECTION,
                format!(
                    "Error de conexión: Timeout ({} ms) al enviar solicitud al demonio.",
                    io_timeout.as_millis()
                ),
            ));
        }
    }

    let _ = stream.shutdown().await;

    let mut response = String::new();
    match timeout(io_timeout, stream.read_to_string(&mut response)).await {
        Ok(Ok(_)) => Ok(response),
        Ok(Err(e)) => Err((
            EXIT_CONNECTION,
            format!(
                "Error de conexión al leer respuesta del demonio ({}). Acción sugerida: verifique si su IP está en tcp_allowlist.",
                e
            ),
        )),
        Err(_) => Err((
            EXIT_CONNECTION,
            format!(
                "Error de conexión: Timeout ({} ms) esperando respuesta del demonio.",
                io_timeout.as_millis()
            ),
        )),
    }
}

fn classify_server_response(response: &str) -> i32 {
    let trimmed = response.trim();
    if trimmed.is_empty() {
        return EXIT_CONNECTION;
    }
    if trimmed.contains("Versión") && trimmed.contains("incompatible")
        || trimmed.contains("Versión menor de protocolo no soportada")
        || trimmed.starts_with("Error de protocolo:")
    {
        return EXIT_PROTOCOL_VERSION;
    }
    if trimmed.starts_with("Error") {
        return EXIT_SERVER_REJECTED;
    }
    EXIT_OK
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let raw_args: Vec<String> = env::args().skip(1).collect();
    let (transport, io_timeout, command_args) = resolve_cli_config(&raw_args);

    if command_args.is_empty() {
        eprintln!(
            "Error de uso: No se especificó ningún comando. Ejecute 'speedyg --help' para ver las opciones."
        );
        process::exit(EXIT_USAGE);
    }

    let command_raw = command_args.join(" ");
    let wire_message = format!("{}\n", attach_version_header(&command_raw));

    let response_result = match transport {
        TransportConfig::Tcp { host, port } => {
            let addr = format!("{}:{}", host, port);
            match timeout(io_timeout, TcpStream::connect(&addr)).await {
                Ok(Ok(stream)) => send_and_receive(stream, &wire_message, io_timeout).await,
                Ok(Err(e)) => {
                    eprintln!(
                        "Error de conexión: No se pudo conectar a {} ({}). Acción sugerida: verifique host, puerto y que speedyg tenga TCP habilitado.",
                        addr, e
                    );
                    process::exit(EXIT_CONNECTION);
                }
                Err(_) => {
                    eprintln!(
                        "Error de conexión: Timeout ({} ms) intentando conectar con {}. Acción sugerida: revise conectividad VPN/LAN o firewall.",
                        io_timeout.as_millis(),
                        addr
                    );
                    process::exit(EXIT_CONNECTION);
                }
            }
        }
        TransportConfig::Unix { socket_path } => {
            match timeout(io_timeout, UnixStream::connect(&socket_path)).await {
                Ok(Ok(stream)) => send_and_receive(stream, &wire_message, io_timeout).await,
                Ok(Err(_)) => {
                    eprintln!(
                        "Error de conexión: El demonio speedyg no está en ejecución en {}. Acción sugerida: inicie 'speedyg' primero.",
                        socket_path
                    );
                    process::exit(EXIT_CONNECTION);
                }
                Err(_) => {
                    eprintln!(
                        "Error de conexión: Timeout ({} ms) conectando al socket {}.",
                        io_timeout.as_millis(),
                        socket_path
                    );
                    process::exit(EXIT_CONNECTION);
                }
            }
        }
    };

    let response = match response_result {
        Ok(resp) => resp,
        Err((code, msg)) => {
            eprintln!("{}", msg);
            process::exit(code);
        }
    };

    if response.trim().is_empty() {
        eprintln!(
            "Error de conexión: El servidor cerró la conexión sin responder. Acción sugerida: verifique que su IP esté autorizada en tcp_allowlist."
        );
        process::exit(EXIT_CONNECTION);
    }

    let exit_code = classify_server_response(&response);
    if exit_code != EXIT_OK {
        eprint!("{}", response);
        process::exit(exit_code);
    }

    print!("{}", response);
    Ok(())
}
