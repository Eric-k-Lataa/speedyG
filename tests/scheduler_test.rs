use speedyG::scheduler::Scheduler;
use speedyG::state_machine::JobState;

#[test]
fn acepta_jobs_mientras_haya_espacio_en_la_cola() {
    let mut scheduler = Scheduler::new();

    assert!(scheduler.add_job("echo".into(), vec!["uno".into()]).is_ok());
    assert!(scheduler.add_job("echo".into(), vec!["dos".into()]).is_ok());
    assert!(scheduler
        .add_job("echo".into(), vec!["tres".into()])
        .is_ok());

    assert_eq!(scheduler.pending_jobs().len(), 3);
}

#[test]
fn rechaza_jobs_cuando_la_cola_esta_llena() {
    let mut scheduler = Scheduler::new();

    for i in 0..3 {
        scheduler
            .add_job("echo".into(), vec![i.to_string()])
            .unwrap();
    }

    let resultado = scheduler.add_job("echo".into(), vec!["cuatro".into()]);

    assert!(resultado.is_err());
    assert_eq!(scheduler.pending_jobs().len(), 3);
}

#[test]
fn permite_agregar_job_despues_de_iniciar_uno() {
    let mut scheduler = Scheduler::new();

    for i in 0..3 {
        scheduler
            .add_job("echo".into(), vec![i.to_string()])
            .unwrap();
    }

    assert!(scheduler.start_job(1));

    let resultado = scheduler.add_job("echo".into(), vec!["nuevo".into()]);

    assert!(resultado.is_ok());
    assert_eq!(scheduler.get_job(1).unwrap().get_state(), JobState::Running);
    assert_eq!(scheduler.pending_jobs().len(), 4);
}

#[test]
fn job_rechazado_no_consume_id() {
    let mut scheduler = Scheduler::new();

    for i in 0..3 {
        scheduler
            .add_job("echo".into(), vec![i.to_string()])
            .unwrap();
    }

    assert!(scheduler
        .add_job("echo".into(), vec!["rechazado".into()])
        .is_err());

    assert!(scheduler.start_job(1));

    let nuevo = scheduler
        .add_job("echo".into(), vec!["nuevo".into()])
        .unwrap();

    assert_eq!(nuevo.get_id(), 4);
}
