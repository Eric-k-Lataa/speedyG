use tracing::warn;

#[derive(Debug, Clone, Copy)]
pub enum JobState {
    Queued,
    Running,
    Succeeded,
    Failed,
    Canceled,
}

#[derive(Debug, Clone, Copy)]
pub enum JobEvent {
    CapacityAvailable,
    Completed,
    Error,
    Cancel,
}

pub struct Job {
    id: u32,
    program: String,
    args: Vec<String>,
    state: JobState,
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

    pub fn transition(&mut self, event: JobEvent) {
        match (self.state, event) {
            (JobState::Queued, JobEvent::CapacityAvailable) => self.state = JobState::Running,
            (JobState::Queued, JobEvent::Cancel) => self.state = JobState::Canceled,
            (JobState::Running, JobEvent::Completed) => self.state = JobState::Succeeded,
            (JobState::Running, JobEvent::Error) => self.state = JobState::Failed,
            (JobState::Running, JobEvent::Cancel) => self.state = JobState::Canceled,
            _ => warn!(
                "Transicion de estado invalida: {:?} + {:?}",
                self.state, event
            ),
        }
    }

}

