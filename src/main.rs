mod parser;
mod state_machine;

use parser::parse;
use state_machine::{JobEvent, JobState, new_job};
use tracing_subscriber;

fn main() {
    tracing_subscriber::fmt::init();

    // Prueba parser
    let command = parse("sleep 10").unwrap();

    println!("Programa: {}", command.program);
    println!("Argumentos: {:?}", command.args);

    let command = parse("health 5");
    match command {
        Ok(command) => {
            println!("Programa:{}", command.program);
            println!("Argumentos:{:?}", command.args);
        }
        Err(error) => {
            println!("Error: {}", error);
        }
    }

    // Pruebas maquina de estados
    let command = parse("sleep 10").unwrap();
    let mut job = new_job(1, command.program, command.args, false);
    JobState::transition(&mut job, JobEvent::Completed);
    println!("{:?}", job.get_state());

    let command = parse("sleep 10").unwrap();
    let mut job = new_job(1, command.program, command.args, false);
    JobState::transition(&mut job, JobEvent::Error);
    println!("{:?}", job.get_state());

    let command = parse("sleep 10").unwrap();
    let mut job = new_job(1, command.program, command.args, false);
    JobState::transition(&mut job, JobEvent::Cancel);
    println!("{:?}", job.get_state());

    let command = parse("sleep 10").unwrap();
    let mut job = new_job(1, command.program, command.args, true);
    JobState::transition(&mut job, JobEvent::CapacityAvailable);
    println!("{:?}", job.get_state());

    //Pruebas de invalidas
    let command = parse("sleep 10").unwrap();
    let mut job = new_job(1, command.program, command.args, true);
    JobState::transition(&mut job, JobEvent::Completed);
    println!("{:?}", job.get_state());

    let command = parse("sleep 10").unwrap();
    let mut job = new_job(1, command.program, command.args, false);
    JobState::transition(&mut job, JobEvent::CapacityAvailable);
    println!("{:?}", job.get_state());

    let command = parse("sleep 10").unwrap();
    let mut job = new_job(1, command.program, command.args, false);
    JobState::transition(&mut job, JobEvent::Completed);
    JobState::transition(&mut job, JobEvent::Error);
    println!("{:?}", job.get_state());

    let command = parse("sleep 10").unwrap();
    let mut job = new_job(1, command.program, command.args, false);
    JobState::transition(&mut job, JobEvent::Error);
    JobState::transition(&mut job, JobEvent::Completed);
    println!("{:?}", job.get_state());
}
