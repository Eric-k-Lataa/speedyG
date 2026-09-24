mod state_machine;

use state_machine::{JobEvent, JobState, new_job};
use tracing_subscriber;

fn main() {
    tracing_subscriber::fmt::init();
    // Pruebas maquina de estados
    let mut job = new_job(1, "sleep 10".to_string(), false);
    JobState::transition(&mut job, JobEvent::Completed);
    println!("{:?}", job.get_state());

    let mut job = new_job(1, "sleep 10".to_string(), false);
    JobState::transition(&mut job, JobEvent::Error);
    println!("{:?}", job.get_state());

    let mut job = new_job(1, "sleep 10".to_string(), false);
    JobState::transition(&mut job, JobEvent::Cancel);
    println!("{:?}", job.get_state());

    let mut job = new_job(1, "sleep 10".to_string(), true);
    JobState::transition(&mut job, JobEvent::CapacityAvailable);
    println!("{:?}", job.get_state());

    //Pruebas de invalidas

    let mut job = new_job(1, "sleep 10".to_string(), true);
    JobState::transition(&mut job, JobEvent::Completed);
    println!("{:?}", job.get_state());

    let mut job = new_job(1, "sleep 10".to_string(), false);
    JobState::transition(&mut job, JobEvent::CapacityAvailable);
    println!("{:?}", job.get_state());

    let mut job = new_job(1, "sleep 10".to_string(), false);
    JobState::transition(&mut job, JobEvent::Completed);
    JobState::transition(&mut job, JobEvent::Error);
    println!("{:?}", job.get_state());

    let mut job = new_job(1, "sleep 10".to_string(), false);
    JobState::transition(&mut job, JobEvent::Error);
    JobState::transition(&mut job, JobEvent::Completed);
    println!("{:?}", job.get_state());
}
