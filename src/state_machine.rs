#[derive(Debug, Clone, Copy)]
pub enum JobState {
    Queued,
    Running,
    Succeeded,
    Failed,
    Canceled,
}

pub enum JobEvent {
    CapacityAvailable,
    Completed,
    Error,
    Cancel,
}

pub struct Job {
    pub id: u32,
    pub command: String,
    state: JobState,
    pub waiting: bool,
}

pub fn new_job(id: u32, command: String, waiting: bool) -> Job {
    let state = if waiting {
        JobState::Queued
    } else {
        JobState::Running
    };

    Job {
        id,
        command,
        state,
        waiting,
    }
}

impl JobState {
    pub fn transition(job: &mut Job, event: JobEvent) {
        match (job.state, event) {
            (JobState::Queued, JobEvent::CapacityAvailable) => {
                job.state = JobState::Running;
                job.waiting = false;
            }

            (JobState::Running, JobEvent::Completed) => job.state = JobState::Succeeded,
            (JobState::Running, JobEvent::Error) => job.state = JobState::Failed,
            (JobState::Running, JobEvent::Cancel) => job.state = JobState::Canceled,
            _ => {}
        }
    }
}
