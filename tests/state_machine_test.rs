use speedyG::state_machine::{new_job, JobEvent, JobState};

#[test]
fn test_queued_to_running_transition() {
    let mut job = new_job(1, "echo".to_string(), vec!["hola".to_string()], true);
    assert_eq!(job.get_state(), JobState::Queued);
    assert_eq!(job.get_exit_code(), None);

    job.transition(JobEvent::CapacityAvailable);
    assert_eq!(job.get_state(), JobState::Running);
}

#[test]
fn test_successful_job_completion() {
    let mut job = new_job(2, "ls".to_string(), vec!["-l".to_string()], false);
    assert_eq!(job.get_state(), JobState::Running);

    // Simulamos la devolución del exit code 0 por parte del executor
    job.transition(JobEvent::Completed(0));
    assert_eq!(job.get_state(), JobState::Succeeded);
    assert_eq!(job.get_exit_code(), Some(0));
}

#[test]
fn test_failed_job_completion() {
    let mut job = new_job(
        3,
        "cat".to_string(),
        vec!["archivo_inexistente.txt".to_string()],
        false,
    );
    assert_eq!(job.get_state(), JobState::Running);

    // Simulamos la devolución del exit code 1 (error general) por parte del executor
    job.transition(JobEvent::Completed(1));
    assert_eq!(job.get_state(), JobState::Failed(1));
    assert_eq!(job.get_exit_code(), Some(1));
}

#[test]
fn test_job_cancellation() {
    let mut job = new_job(4, "sleep".to_string(), vec!["60".to_string()], true);

    // Cancelar mientras está en cola
    job.transition(JobEvent::Cancel);
    assert_eq!(job.get_state(), JobState::Canceled);
    assert_eq!(job.get_exit_code(), None);
}
