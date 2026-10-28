use std::fmt;
use tracing::warn;
use serde::{Serialize, Deserialize};

pub const EXIT_INTERRUMPIDO: i32 = -1;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum JobState {
    Queued,
    Running,
    Succeeded,
    Failed(i32), // Guarda el codigo de error (esto lo añadí yo Caro)
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
}

pub fn new_job(id: u32, program: String, args: Vec<String>, waiting: bool) -> Job {
    let state = if waiting {
        JobState::Queued
    } else {
        JobState::Running
    };

    Job {
        id,
        program,
        args,
        state,
        exit_code: None,
    }
}

impl fmt::Display for Job {
    // Es como un printer por así decirlo
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let args_str = if self.get_args().is_empty() {
            String::new()
        } else {
            format!(" {}", self.get_args().join(" "))
        };
        match self.get_exit_code() {
            Some(code) => write!(
                f,
                "Job #{}: {}{} [{:?}] (exit code: {})",
                self.get_id(),
                self.get_program(),
                args_str,
                self.get_state(),
                code
            ),
            None => write!(
                f,
                "Job #{}: {}{} [{:?}]",
                self.get_id(),
                self.get_program(),
                args_str,
                self.get_state()
            ),
        }
    }
}

impl Job {

    //Recontruccion de un job para la persistencia
    pub fn from_parts(
        id: u32,
        program: String,
        args: Vec<String>,
        state: JobState,
        exit_code: Option<i32>,
    ) -> Job {
        Job {
            id,
            program,
            args,
            state,
            exit_code,
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



    //
    pub fn get_command_line(&self) -> String {
        if self.args.is_empty() {
            self.program.clone()
        } else {
            format!("{} {}", self.program, self.args.join(" "))
        }
    }

    pub fn transition(&mut self, event: JobEvent) {
        match (self.state, event) {
            (JobState::Queued, JobEvent::CapacityAvailable) => {
                self.state = JobState::Running;
            }
            (JobState::Queued, JobEvent::Cancel) => {
                self.state = JobState::Canceled;
            }
            (JobState::Running, JobEvent::Completed(code)) => {
                self.exit_code = Some(code);
                if code == 0 {
                    self.state = JobState::Succeeded;
                } else {
                    self.state = JobState::Failed(code);
                }
            }
            (JobState::Running, JobEvent::Cancel) => {
                self.state = JobState::Canceled;
            }
            (JobState::Running, JobEvent::ServiceRestarted) => {
                self.state = JobState::Interrupted;
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


