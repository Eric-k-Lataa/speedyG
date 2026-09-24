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
    command: String,
    state: JobState,
}

pub fn new_job(id: u32, command: String, waiting: bool) -> Job {
    let state = if waiting {
        JobState::Queued
    } else {
        JobState::Running
    };

    Job { id, command, state }
}

impl Job {
    pub fn get_id(&self) -> u32 {
        self.id
    }
    pub fn get_command(&self) -> &str {
        &self.command
    }

    pub fn get_state(&self) -> JobState {
        self.state
    }
}

impl JobState {
    pub fn transition(job: &mut Job, event: JobEvent) {
        match (job.state, event) {
            (JobState::Queued, JobEvent::CapacityAvailable) => job.state = JobState::Running,
            (JobState::Queued, JobEvent::Cancel) => job.state = JobState::Canceled,
            (JobState::Running, JobEvent::Completed) => job.state = JobState::Succeeded,
            (JobState::Running, JobEvent::Error) => job.state = JobState::Failed,
            (JobState::Running, JobEvent::Cancel) => job.state = JobState::Canceled,
            _ => warn!(
                "Transicion de estado invalida: {:?} + {:?}",
                job.state, event
            ),
        }
    }
}
