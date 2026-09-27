
use crate::parser::parse;
use crate::state_machine::{new_job,JobEvent};

pub fn run_tests(){
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
    job.transition( JobEvent::Completed);
    println!("{:?}", job.get_state());

    let command = parse("sleep 10").unwrap();
    let mut job = new_job(1, command.program, command.args, false);
    job.transition(JobEvent::Error);
    println!("{:?}", job.get_state());

    let command = parse("sleep 10").unwrap();
    let mut job = new_job(1, command.program, command.args, false);
    job.transition(JobEvent::Cancel);
    println!("{:?}", job.get_state());

    let command = parse("sleep 10").unwrap();
    let mut job = new_job(1, command.program, command.args, true);
    job.transition(JobEvent::CapacityAvailable);
    println!("{:?}", job.get_state());

    //Pruebas de invalidas
    let command = parse("sleep 10").unwrap();
    let mut job = new_job(1, command.program, command.args, true);
    job.transition(JobEvent::Completed);
    println!("{:?}", job.get_state());

    let command = parse("sleep 10").unwrap();
    let mut job = new_job(1, command.program, command.args, false);
    job.transition(JobEvent::CapacityAvailable);
    println!("{:?}", job.get_state());

    let command = parse("sleep 10").unwrap();
    let mut job = new_job(1, command.program, command.args, false);
    job.transition(JobEvent::Completed);
    job.transition(JobEvent::Error);
    println!("{:?}", job.get_state());

    let command = parse("sleep 10").unwrap();
    let mut job = new_job(1, command.program, command.args, false);
    job.transition(JobEvent::Error);
    job.transition(JobEvent::Completed);
    println!("{:?}", job.get_state());

}
