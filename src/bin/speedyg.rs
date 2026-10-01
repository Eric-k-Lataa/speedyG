use std::env;
use std::process;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::UnixStream;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = env::args().skip(1).collect();
    if args.is_empty() {
        eprintln!("Uso: speedyg <comando>");
        process::exit(2); // code 2, uso incorrecto argumentos
    }

    let command_raw = args.join(" ");
    let socket_path = "/tmp/speedyg.sock";

    let mut stream = match UnixStream::connect(socket_path).await {
        Ok(stream) => stream,
        Err(_) => {
            eprintln!("Error: El demonio speedyg no está en ejecución.");
            process::exit(1); // code 1, error general
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
