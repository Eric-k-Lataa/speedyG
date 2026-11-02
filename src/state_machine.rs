use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::fmt;
use tracing::warn;

pub const EXIT_INTERRUMPIDO: i32 = -1;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum JobState {
    Queued,
    Running,
    Succeeded,
    Failed(i32),     // Guarda el codigo de error
    KillSignal(i32), // Guarda la señal que mato al proceso
    Canceled,
    Interrupted,
}

impl JobState {
    pub fn to_db(self) -> &'static str {
        match self {
            JobState::Queued => "Queued",
            JobState::Running => "Running",
            JobState::Succeeded => "Succeeded",
            JobState::Failed(_) => "Failed",
            JobState::KillSignal(_) => "KillSignal",
            JobState::Canceled => "Canceled",
            JobState::Interrupted => "Interrupted",
        }
    }

    pub fn from_db(state: &str, exit_code: Option<i32>) -> Option<JobState> {
        match state {
            "Queued" => Some(JobState::Queued),
            "Running" => Some(JobState::Running),
            "Succeeded" => Some(JobState::Succeeded),
            "Failed" => Some(JobState::Failed(exit_code.unwrap_or(EXIT_INTERRUMPIDO))),
            "KillSignal" => Some(JobState::KillSignal(exit_code.unwrap_or(EXIT_INTERRUMPIDO))),
            "Canceled" => Some(JobState::Canceled),
            "Interrupted" => Some(JobState::Interrupted),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum JobEvent {
    CapacityAvailable,
    Completed(i32), // Mismo caso que para Failed
    // Error, //Segun yo, teniendo la definición del Completed, no hace falta si es error
    KillSignal(i32),
    Cancel,
    ServiceRestarted,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Job {
    id: u32,
    program: String,
    args: Vec<String>,
    state: JobState,
    exit_code: Option<i32>, // Almacena el codigo de salida
    stdout: Option<String>,
    stderr: Option<String>,
    received_at: DateTime<Utc>,
    started_at: Option<DateTime<Utc>>,
    finished_at: Option<DateTime<Utc>>,
}

pub fn new_job(id: u32, program: String, args: Vec<String>, waiting: bool) -> Job {
    let state = if waiting {
        JobState::Queued
    } else {
        JobState::Running
    };

    let now = Utc::now();
    Job {
        id,
        program,
        args,
        state,
        exit_code: None,
        stdout: None,
        stderr: None,
        received_at: now,
        started_at: if !waiting { Some(now) } else { None },
        finished_at: None,
    }
}

// Función auxiliar para el display de los procesos
fn indent_text(text: &str) -> String {
    text.lines()
        .map(|line| format!("    │ {}", line))
        .collect::<Vec<_>>()
        .join("\n")
}

// Vista detallada completa exclusiva para status <id>
impl fmt::Display for Job {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let received = self.received_at.format("%Y-%m-%d %H:%M:%S UTC");
        let started = self
            .started_at
            .map(|t| t.format("%Y-%m-%d %H:%M:%S UTC").to_string())
            .unwrap_or_else(|| "Pendiente".to_string());
        let finished = self
            .finished_at
            .map(|t| t.format("%Y-%m-%d %H:%M:%S UTC").to_string())
            .unwrap_or_else(|| "En curso / No finalizado".to_string());

        let exit_info = match self.exit_code {
            Some(code) => format!(" (exit code: {})", code),
            None => String::new(),
        };

        // Cabecera e info temporal
        writeln!(
            f,
            "Job #{}: {}{} [{:?}]{}\n  ├─ Recibido:  {}\n  ├─ Iniciado:  {}\n  └─ Finalizado: {}",
            self.id,
            self.program,
            if self.args.is_empty() {
                String::new()
            } else {
                format!(" {}", self.args.join(" "))
            },
            self.state,
            exit_info,
            received,
            started,
            finished
        )?;

        // Salida estándar separada (RF-11)
        if let Some(ref out) = self.stdout {
            if !out.is_empty() {
                writeln!(f, "  [stdout]:\n{}", indent_text(out))?;
            }
        }

        // Error estándar separado (RF-11)
        if let Some(ref err) = self.stderr {
            if !err.is_empty() {
                writeln!(f, "  [stderr]:\n{}", indent_text(err))?;
            }
        }

        Ok(())
    }
}

impl Job {
    // Vista compacta para la lista general o filtros de estado
    pub fn summary_string(&self) -> String {
        let args_str = if self.args.is_empty() {
            String::new()
        } else {
            format!(" {}", self.args.join(" "))
        };

        match self.exit_code {
            Some(code) => format!(
                "Job #{}: {}{} [{:?}] (exit code: {})",
                self.id, self.program, args_str, self.state, code
            ),
            None => format!(
                "Job #{}: {}{} [{:?}]",
                self.id, self.program, args_str, self.state
            ),
        }
    }

    //"setter" para las salidas
    pub fn set_output(&mut self, stdout: String, stderr: String) {
        self.stdout = Some(stdout);
        self.stderr = Some(stderr);
    }

    pub fn finish_execution(&mut self, exit_code: i32, stdout: String, stderr: String) -> bool {
        // Si ya estaba cancelado, no sobreescribimos su estado final
        if matches!(self.state, JobState::Canceled) {
            return false;
        }

        self.exit_code = Some(exit_code);
        self.stdout = Some(stdout);
        self.stderr = Some(stderr);
        self.finished_at = Some(Utc::now());

        self.state = if exit_code == 0 {
            JobState::Succeeded
        } else {
            JobState::Failed(exit_code)
        };

        true
    }

    //Recontruccion de un job para la persistencia
    #[allow(clippy::too_many_arguments)]
    pub fn from_parts(
        id: u32,
        program: String,
        args: Vec<String>,
        state: JobState,
        exit_code: Option<i32>,
        stdout: Option<String>,
        stderr: Option<String>,
        received_at: DateTime<Utc>,
        started_at: Option<DateTime<Utc>>,
        finished_at: Option<DateTime<Utc>>,
    ) -> Job {
        Job {
            id,
            program,
            args,
            state,
            exit_code,
            stdout,
            stderr,
            received_at,
            started_at,
            finished_at,
        }
    }

    pub fn get_id(&self) -> u32 {
        self.id
    }
    pub fn get_program(&self) -> &str {
        &self.program
    }

    pub fn get_state(&self) -> JobState {
        self.state
    }

    pub fn get_args(&self) -> &Vec<String> {
        &self.args
    }

    pub fn get_exit_code(&self) -> Option<i32> {
        self.exit_code
    }

    pub fn get_stdout(&self) -> Option<&String> {
        self.stdout.as_ref()
    }

    pub fn get_stderr(&self) -> Option<&String> {
        self.stderr.as_ref()
    }

    pub fn get_received_at(&self) -> DateTime<Utc> {
        self.received_at
    }

    pub fn get_started_at(&self) -> Option<DateTime<Utc>> {
        self.started_at
    }

    pub fn get_finished_at(&self) -> Option<DateTime<Utc>> {
        self.finished_at
    }

    //
    pub fn get_command_line(&self) -> String {
        if self.args.is_empty() {
            self.program.clone()
        } else {
            format!("{} {}", self.program, self.args.join(" "))
        }
    }

    pub fn transition(&mut self, event: JobEvent) {
        let now = Utc::now();
        match (self.state, event) {
            (JobState::Queued, JobEvent::CapacityAvailable) => {
                self.state = JobState::Running;
                self.started_at = Some(now);
            }
            (JobState::Queued, JobEvent::Cancel) => {
                self.state = JobState::Canceled;
                self.finished_at = Some(now);
            }
            (JobState::Running, JobEvent::Completed(code)) => {
                self.exit_code = Some(code);
                self.finished_at = Some(now);
                if code == 0 {
                    self.state = JobState::Succeeded;
                } else {
                    self.state = JobState::Failed(code);
                }
            }
            (JobState::Running, JobEvent::KillSignal(sig)) => {
                self.exit_code = Some(sig);
                self.finished_at = Some(now);
                self.state = JobState::KillSignal(sig);
            }
            (JobState::Running, JobEvent::Cancel) => {
                self.state = JobState::Canceled;
                self.finished_at = Some(now);
            }
            (JobState::Running, JobEvent::ServiceRestarted) => {
                self.state = JobState::Interrupted;
                self.finished_at = Some(now);
            }
            (JobState::Queued, JobEvent::ServiceRestarted) => {
                // el trabajo permanece en la cola
            }
            (
                JobState::Succeeded
                | JobState::Failed(_)
                | JobState::Canceled
                | JobState::Interrupted,
                JobEvent::ServiceRestarted,
            ) => {
                // Los estados terminales se conservan tras el reinicio
            }
            _ => warn!(
                "Transición de estado inválida: {:?} + {:?}",
                self.state, event
            ),
        }
    }
}
