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

#[test]
fn test_running_to_canceled_transition() {
    let mut job = new_job(5, "sleep".to_string(), vec!["60".to_string()], false);

    job.transition(JobEvent::Cancel);

    assert_eq!(job.get_state(), JobState::Canceled);
}

#[test]
fn test_running_to_interrupted_transition() {
    let mut job = new_job(6, "sleep".to_string(), vec!["60".to_string()], false);

    job.transition(JobEvent::ServiceRestarted);

    assert_eq!(job.get_state(), JobState::Interrupted);
}

#[test]
fn test_succeeded_remains_after_restart() {
    let mut job = new_job(8, "echo".to_string(), vec![], false);
    job.transition(JobEvent::Completed(0));

    job.transition(JobEvent::ServiceRestarted);

    assert_eq!(job.get_state(), JobState::Succeeded);
}

#[test]
fn test_failed_remains_after_restart() {
    let mut job = new_job(9, "cat".to_string(), vec![], false);
    job.transition(JobEvent::Completed(1));

    job.transition(JobEvent::ServiceRestarted);

    assert_eq!(job.get_state(), JobState::Failed(1));
}

#[test]
fn test_canceled_remains_after_restart() {
    let mut job = new_job(10, "sleep".to_string(), vec![], false);
    job.transition(JobEvent::Cancel);

    job.transition(JobEvent::ServiceRestarted);

    assert_eq!(job.get_state(), JobState::Canceled);
}

#[test]
fn test_interrupted_remains_after_restart() {
    let mut job = new_job(11, "sleep".to_string(), vec![], false);
    job.transition(JobEvent::ServiceRestarted);

    job.transition(JobEvent::ServiceRestarted);

    assert_eq!(job.get_state(), JobState::Interrupted);
}

#[test]
fn test_queued_cannot_complete() {
    let mut job = new_job(12, "echo".to_string(), vec![], true);

    job.transition(JobEvent::Completed(0));

    assert_eq!(job.get_state(), JobState::Queued);
}

#[test]
fn test_queued_cannot_become_failed() {
    let mut job = new_job(13, "echo".to_string(), vec![], true);

    job.transition(JobEvent::Completed(1));

    assert_eq!(job.get_state(), JobState::Queued);
}

#[test]
fn test_queued_cannot_become_interrupted() {
    let mut job = new_job(14, "echo".to_string(), vec![], true);

    job.transition(JobEvent::ServiceRestarted);

    // ServiceRestarted está permitido para Queued según la implementación actual.
    // Por eso, este caso no es una transición inválida.
    assert_eq!(job.get_state(), JobState::Queued);
}

#[test]
fn test_running_cannot_return_to_queued() {
    let mut job = new_job(15, "echo".to_string(), vec![], false);

    job.transition(JobEvent::CapacityAvailable);

    assert_eq!(job.get_state(), JobState::Running);
}

#[test]
fn test_succeeded_cannot_return_to_running() {
    let mut job = new_job(16, "echo".to_string(), vec![], false);
    job.transition(JobEvent::Completed(0));

    job.transition(JobEvent::CapacityAvailable);

    assert_eq!(job.get_state(), JobState::Succeeded);
}

#[test]
fn test_failed_cannot_return_to_running() {
    let mut job = new_job(17, "cat".to_string(), vec![], false);
    job.transition(JobEvent::Completed(1));

    job.transition(JobEvent::CapacityAvailable);

    assert_eq!(job.get_state(), JobState::Failed(1));
}

#[test]
fn test_canceled_cannot_return_to_running() {
    let mut job = new_job(18, "sleep".to_string(), vec![], false);
    job.transition(JobEvent::Cancel);

    job.transition(JobEvent::CapacityAvailable);

    assert_eq!(job.get_state(), JobState::Canceled);
}

#[test]
fn test_interrupted_cannot_return_to_running() {
    let mut job = new_job(19, "sleep".to_string(), vec![], false);
    job.transition(JobEvent::ServiceRestarted);

    job.transition(JobEvent::CapacityAvailable);

    assert_eq!(job.get_state(), JobState::Interrupted);
}

#[test]
fn test_succeeded_cannot_become_failed() {
    let mut job = new_job(20, "echo".to_string(), vec![], false);
    job.transition(JobEvent::Completed(0));

    job.transition(JobEvent::Completed(1));

    assert_eq!(job.get_state(), JobState::Succeeded);
}

#[test]
fn test_failed_cannot_become_succeeded() {
    let mut job = new_job(21, "cat".to_string(), vec![], false);
    job.transition(JobEvent::Completed(1));

    job.transition(JobEvent::Completed(0));

    assert_eq!(job.get_state(), JobState::Failed(1));
}

#[test]
fn test_canceled_cannot_become_succeeded() {
    let mut job = new_job(22, "sleep".to_string(), vec![], false);
    job.transition(JobEvent::Cancel);

    job.transition(JobEvent::Completed(0));

    assert_eq!(job.get_state(), JobState::Canceled);
}

#[test]
fn test_interrupted_cannot_become_succeeded() {
    let mut job = new_job(23, "sleep".to_string(), vec![], false);
    job.transition(JobEvent::ServiceRestarted);

    job.transition(JobEvent::Completed(0));

    assert_eq!(job.get_state(), JobState::Interrupted);
}

#[test]
fn test_canceled_cannot_be_canceled_again() {
    let mut job = new_job(24, "echo".to_string(), vec![], true);

    job.transition(JobEvent::Cancel);
    job.transition(JobEvent::Cancel);

    assert_eq!(job.get_state(), JobState::Canceled);
}

#[test]
fn test_succeeded_cannot_be_canceled() {
    let mut job = new_job(25, "echo".to_string(), vec![], false);
    job.transition(JobEvent::Completed(0));

    job.transition(JobEvent::Cancel);

    assert_eq!(job.get_state(), JobState::Succeeded);
}

#[test]
fn test_failed_cannot_be_canceled() {
    let mut job = new_job(26, "cat".to_string(), vec![], false);
    job.transition(JobEvent::Completed(1));

    job.transition(JobEvent::Cancel);

    assert_eq!(job.get_state(), JobState::Failed(1));
}

#[test]
fn test_interrupted_cannot_be_canceled() {
    let mut job = new_job(27, "sleep".to_string(), vec![], false);
    job.transition(JobEvent::ServiceRestarted);

    job.transition(JobEvent::Cancel);

    assert_eq!(job.get_state(), JobState::Interrupted);
}

#[test]
fn test_succeeded_cannot_be_interrupted() {
    let mut job = new_job(28, "echo".to_string(), vec![], false);
    job.transition(JobEvent::Completed(0));

    job.transition(JobEvent::ServiceRestarted);

    assert_eq!(job.get_state(), JobState::Succeeded);
}

#[test]
fn test_failed_cannot_be_interrupted() {
    let mut job = new_job(29, "cat".to_string(), vec![], false);
    job.transition(JobEvent::Completed(1));

    job.transition(JobEvent::ServiceRestarted);

    assert_eq!(job.get_state(), JobState::Failed(1));
}

#[test]
fn test_canceled_cannot_be_interrupted() {
    let mut job = new_job(30, "sleep".to_string(), vec![], false);
    job.transition(JobEvent::Cancel);

    job.transition(JobEvent::ServiceRestarted);

    assert_eq!(job.get_state(), JobState::Canceled);
}

#[test]
fn test_interrupted_cannot_be_complete() {
    let mut job = new_job(31, "sleep".to_string(), vec![], false);

    job.transition(JobEvent::ServiceRestarted);
    job.transition(JobEvent::Completed(0));

    assert_eq!(job.get_state(), JobState::Interrupted);
}

#[test]
fn test_running_cannot_become_queued() {
    let mut job = new_job(32, "echo".to_string(), vec![], false);

    job.transition(JobEvent::CapacityAvailable);

    assert_eq!(job.get_state(), JobState::Running);
}
