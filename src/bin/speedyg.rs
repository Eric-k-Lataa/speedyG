// src/bin/speedyg.rs

// Cliente CLI del demonio speedyG.
// El socket al que se conecta se determnina en este orden:
//      1. Flag --socket <ruta>
//      2. Variable de entorno SPEEDYG_SOCKET
//      3. Valor por defecto: /tmp/speedyg.sock

use std::env;
use std::process;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::UnixStream;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let raw_args: Vec<String> = env::args().skip(1).collect();

    let mut _socket_path =
        env::var("SPEEDYG_SOCKET").unwrap_or_else(|_| "/tmp/speedyg.sock".to_string());
    let mut command_args: Vec<String> = Vec::new();

    let mut i = 0;
    while i < raw_args.len() {
        if raw_args[i] == "--socket" {
            if let Some(val) = raw_args.get(i + 1) {
                _socket_path = val.clone();
                i += 2;
            } else {
                eprintln!("Error: Falta el valor para la opción --socket");
                process::exit(2);
            }
        } else {
            command_args.push(raw_args[i].clone());
            i += 1;
        }
    }
    if command_args.is_empty() {
        eprintln!("Uso: speedyg [--socket <path>] <comando> [args...]");
        process::exit(2);
    }

    let command_raw = command_args.join(" ");

    let mut stream = match UnixStream::connect(&_socket_path).await {
        Ok(stream) => stream,
        Err(_) => {
            eprintln!(
                "Error: El demonio speedyg no está en ejecución (socket: {}).",
                _socket_path
            );
            process::exit(1);
        }
    };

    if let Err(e) = stream.write_all(command_raw.as_bytes()).await {
        eprintln!("Error al enviar datos al demonio: {}", e);
        process::exit(1);
    }

    //stream.write_all(command_raw.as_bytes()).await?;
    stream.shutdown().await?;

    let mut response = String::new();
    stream.read_to_string(&mut response).await?;
    print!("{}", response);

    Ok(())
}
