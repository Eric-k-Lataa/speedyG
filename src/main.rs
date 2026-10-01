mod executor;
mod parser;
mod scheduler;
mod state_machine;

use std::fs;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::mpsc;

use parser::ParsedCommand;
use state_machine::{new_job, Job, JobEvent};

const SOCKET_PATH: &str = "/tmp/speedyg.sock";

/// Eventos del Event Loop del Daemon
#[derive(Debug)]
pub enum SystemEvent {
    /// Llegó un comando válido desde la CLI `speedyg`
    NewCommand {
        cmd: ParsedCommand,
        // Canal para responder directamente al cliente CLI que envió el comando
        responder: tokio::sync::oneshot::Sender<String>,
    },
    /// Un Job terminó de ejecutarse
    JobFinished { id: u32, success: bool },
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("Iniciando Daemon speedyg...");

    if fs::metadata(SOCKET_PATH).is_ok() {
        fs::remove_file(SOCKET_PATH)?;
    }

    let listener = UnixListener::bind(SOCKET_PATH)?;
    println!("Demonio escuchando en {}", SOCKET_PATH);

    // Canal principal del Event Loop (MPSC)
    let (event_tx, mut event_rx) = mpsc::channel::<SystemEvent>(32);

    // Contador de IDs para Jobs (temporal hasta integrarlo en Scheduler)
    let mut next_job_id: u32 = 1;

    loop {
        tokio::select! {
            // 1. Aceptar conexiones entrantes del socket IPC
            Ok((stream, _)) = listener.accept() => {
                let tx = event_tx.clone();
                tokio::spawn(async move {
                    if let Err(e) = handle_client(stream, tx).await {
                        eprintln!("Error procesando cliente: {}", e);
                    }
                });
            }

            // 2. Event Loop Principal: Procesar eventos del sistema
            Some(event) = event_rx.recv() => {
                match event {
                    SystemEvent::NewCommand { cmd, responder } => {
                        let response = process_command(cmd, &mut next_job_id).await;
                        let _ = responder.send(response);
                    }
                    SystemEvent::JobFinished { id, success } => {
                        println!("Evento recibido: Job {} finalizado (Éxito: {})", id, success);
                        // Aquí el Scheduler buscaría el Job y llamaría a:
                        // job.transition(if success { JobEvent::Completed } else { JobEvent::Error });
                    }
                }
            }
        }
    }
}

/// Atiende la conexión individual de un usuario ejecutando `speedyg <cmd>`
async fn handle_client(
    mut stream: UnixStream,
    event_tx: mpsc::Sender<SystemEvent>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let mut buffer = String::new();
    stream.read_to_string(&mut buffer).await?;
    let input = buffer.trim();

    if input.is_empty() {
        return Ok(());
    }

    // Usamos TU parser.rs
    match parser::parse(input) {
        Ok(cmd) => {
            let (resp_tx, resp_rx) = tokio::sync::oneshot::channel();

            // Enviar comando al Event Loop
            event_tx
                .send(SystemEvent::NewCommand {
                    cmd,
                    responder: resp_tx,
                })
                .await?;

            // Esperar la respuesta procesada por el Event Loop
            if let Ok(response) = resp_rx.await {
                stream.write_all(response.as_bytes()).await?;
            }
        }
        Err(err) => {
            let error_msg = format!("Error de sintaxis: {}\n", err);
            stream.write_all(error_msg.as_bytes()).await?;
        }
    }

    Ok(())
}

/// Procesa la lógica de negocio según el tipo de comando parseado
async fn process_command(cmd: ParsedCommand, next_job_id: &mut u32) -> String {
    match cmd.program.as_str() {
        "help" => {
            "Comandos disponibles: status <id>, cancel <id>, sleep <sec>, echo <txt>, health, ls, help\n".to_string()
        }
        "health" => {
            "OK: Daemon speedyg funcionando correctamente\n".to_string()
        }
        "status" => {
            let job_id = cmd.args[0].parse::<u32>().unwrap();
            format!("Consultando estado del Job {}\n", job_id)
        }
        "cancel" => {
            let job_id = cmd.args[0].parse::<u32>().unwrap();
            format!("Cancelando Job {}\n", job_id)
        }
        // Comandos de ejecución que crean un Job con FSM
        "sleep" | "echo" | "ls" => {
            let job_id = *next_job_id;
            *next_job_id += 1;

            // Instanciamos TU struct Job de state_machine.rs
            let mut job: Job = new_job(job_id, cmd.program, cmd.args, true);
            // La FSM transiciona al ser enviado a ejecución
            job.transition(JobEvent::CapacityAvailable);

            format!("Job {} creado en estado: {:?}\n", job.get_id(), job.get_state())
        }
        _ => "Comando no reconocido\n".to_string(),
    }
}
