#[derive(Debug)]
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

pub fn initial_state(has_capacity: bool) -> JobState {
    if has_capacity {
        JobState::Running
    } else {
        JobState::Queued
    }
}

impl JobState {
    pub fn transition(self, event: JobEvent) -> Option<JobState> {
        match (self, event) {
            (JobState::Queued, JobEvent::CapacityAvailable) => Some(JobState::Running),
            (JobState::Running, JobEvent::Completed) => Some(JobState::Succeeded),
            (JobState::Running, JobEvent::Error) => Some(JobState::Failed),
            (JobState::Running, JobEvent::Cancel) => Some(JobState::Canceled),
            _ => None,
        }
    }
}
