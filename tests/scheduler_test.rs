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

#[test]
fn respeta_el_limite_de_trabajos_concurrentes() {
    let mut scheduler = Scheduler::new();

    for i in 0..3 {
        scheduler
            .add_job("echo".into(), vec![i.to_string()])
            .unwrap();
    }

    for _ in 0..3 {
        assert!(scheduler.start_next_job(3).is_some());
    }

    assert!(scheduler.start_next_job(3).is_none());

    let running = scheduler
        .pending_jobs()
        .iter()
        .filter(|job| job.get_state() == JobState::Running)
        .count();

    assert_eq!(running, 3);
}

#[test]
fn inicia_el_siguiente_job_cuando_hay_capacidad() {
    let mut scheduler = Scheduler::new();

    for i in 0..3 {
        scheduler
            .add_job("echo".into(), vec![i.to_string()])
            .unwrap();
    }

    for _ in 0..3 {
        scheduler.start_next_job(3).unwrap();
    }

    assert!(scheduler.complete_job(1, 0));

    let nuevo_id = scheduler
        .add_job("echo".into(), vec!["nuevo".into()])
        .unwrap()
        .get_id();

    let siguiente = scheduler.start_next_job(3);

    assert_eq!(siguiente.unwrap().0, nuevo_id);
}

#[test]
fn no_inicia_jobs_si_el_limite_es_cero() {
    let mut scheduler = Scheduler::new();

    scheduler
        .add_job("echo".into(), vec!["uno".into()])
        .unwrap();

    assert!(scheduler.start_next_job(0).is_none());
    assert_eq!(scheduler.get_job(1).unwrap().get_state(), JobState::Queued);
}
