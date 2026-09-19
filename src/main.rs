mod state_machine;

use state_machine::{JobEvent, JobState, initial_state};

fn main() {

// Pruebas maquina de estados
    let state = JobState::Queued;
    let next_state = state.transition(JobEvent::CapacityAvailable);
    println!("{:?}", next_state);

    let state = JobState::Running;
    let next_state = state.transition(JobEvent::Completed);
    println!("{:?}", next_state);

    let state = JobState::Running;
    let next_state = state.transition(JobEvent::Error);
    println!("{:?}", next_state);

    let state = JobState::Running;
    let next_state = state.transition(JobEvent::Cancel);
    println!("{:?}", next_state);


//Pruebas estado inicial
    let state = initial_state(true);
    println!("{:?}",state);

    let state = initial_state(false);
    println!("{:?}",state);


//Pruebas maquina de estados, eventos invalidos

// Pruebas maquina de estados
    let state = JobState::Queued;
    let next_state = state.transition(JobEvent::Completed);
    println!("{:?}", next_state);

    let state = JobState::Running;
    let next_state = state.transition(JobEvent::CapacityAvailable);
    println!("{:?}", next_state);

    let state = JobState::Succeeded;
    let next_state = state.transition(JobEvent::Completed);
    println!("{:?}", next_state);

    let state = JobState::Failed;
    let next_state = state.transition(JobEvent::Completed);
    println!("{:?}", next_state);


}
