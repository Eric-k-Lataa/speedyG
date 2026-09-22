mod state_machine;

use state_machine::{JobEvent, JobState, new_job};

fn main() {
    // Pruebas maquina de estados
    let mut job = new_job(1, "sleep 10".to_string(), false);
    JobState::transition(&mut job, JobEvent::Completed);
    println!("{:?}", job.state);

    let mut job = new_job(1, "sleep 10".to_string(), false);
    JobState::transition(&mut job, JobEvent::Error);
    println!("{:?}", job.state);

    let mut job = new_job(1, "sleep 10".to_string(), false);
    JobState::transition(&mut job, JobEvent::Cancel);
    println!("{:?}", job.state);

    let mut job = new_job(1, "sleep 10".to_string(), true);
    JobState::transition(&mut job, JobEvent::CapacityAvailable);
    println!("{:?}", job.state);

    //Pruebas de invalidas

    let mut job = new_job(1, "sleep 10".to_string(), true);
    JobState::transition(&mut job, JobEvent::Completed);
    println!("{:?}", job.state);

    let mut job = new_job(1, "sleep 10".to_string(), false);
    JobState::transition(&mut job, JobEvent::CapacityAvailable);
    println!("{:?}", job.state);

    let mut job = new_job(1, "sleep 10".to_string(), false);
    JobState::transition(&mut job, JobEvent::Completed);
    JobState::transition(&mut job, JobEvent::Error);
    println!("{:?}", job.state);

    let mut job = new_job(1, "sleep 10".to_string(), false);
    JobState::transition(&mut job, JobEvent::Error);
    JobState::transition(&mut job, JobEvent::Completed);
    println!("{:?}", job.state);
}
