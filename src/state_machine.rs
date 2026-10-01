use tracing::warn;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum JobState {
    Queued,
    Running,
    Succeeded,
    Failed(i32), // Guarda el codigo de error (esto lo añadí yo Caro)
    Canceled,
}

#[derive(Debug, Clone, Copy)]
pub enum JobEvent {
    CapacityAvailable,
    Completed(i32), // Mismo caso que para Failed
    // Error, //Segun yo, teniendo la definición del Completed, no hace falta si es error
    Cancel,
}

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

impl Job {
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

    // Tambien cambie esta función Caro, sorry :<
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
            _ => warn!(
                "Transición de estado inválida: {:?} + {:?}",
                self.state, event
            ),
        }
    }
}
