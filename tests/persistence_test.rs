use speedyG::persistence::{cargar_desde, guardar_en};
use speedyG::scheduler::Scheduler;
use speedyG::state_machine::JobState;
use std::fs;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Instant;


fn rutas(nombre: &str) -> (PathBuf, PathBuf, PathBuf) {
    let dir = std::env::temp_dir().join(format!("speedyg_test_{}_{}", nombre, std::process::id()));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).unwrap();
    (dir.join("speedyg.db"), dir.join("scheduler.json"), dir)
}

fn texto(s: &Scheduler) -> Vec<String> {
    s.pending_jobs()
        .iter()
        .chain(s.history_jobs().iter())
        .map(|j| j.to_string())
        .collect()
}


fn scheduler_ejemplo() -> Scheduler {
    let mut s = Scheduler::new();
    for (p, a) in [
        ("echo", "hola"),
        ("sh", "-c"),
        ("sleep", "100"),
        ("sleep", "10"),
        ("ls", "-l"),
    ] {
        s.add_job(p.to_string(), vec![a.to_string()]);
    }
    s.start_job(1);
    s.complete_job(1, 0);
    s.start_job(2);
    s.complete_job(2, 3);
    s.cancel_job(3);
    s.start_job(4);
    s
}

#[test]
fn guardar_y_cargar_conserva_todo() {
    let (db, json, dir) = rutas("roundtrip");
    let original = scheduler_ejemplo();
    guardar_en(&original, &db, &json).unwrap();

    let cargado = cargar_desde(&db, &json);
    assert_eq!(texto(&original), texto(&cargado));
    assert_eq!(original.next_id(), cargado.next_id());
    assert_eq!(cargado.get_job(2).unwrap().get_state(), JobState::Failed(3));
    assert_eq!(cargado.get_job(3).unwrap().get_state(), JobState::Canceled);
    let _ = fs::remove_dir_all(dir);
}

#[test]
fn cancelacion_se_refleja_en_persistencia() {
    let (db, json, dir) = rutas("cancel");
    let mut s = Scheduler::new();
    s.add_job("sleep".into(), vec!["60".into()]);
    guardar_en(&s, &db, &json).unwrap();

    assert!(s.cancel_job(1));
    guardar_en(&s, &db, &json).unwrap();

    let cargado = cargar_desde(&db, &json);
    assert_eq!(cargado.get_job(1).unwrap().get_state(), JobState::Canceled);
    assert!(cargado.pending_jobs().is_empty());
    let _ = fs::remove_dir_all(dir);
}

#[test]
fn recuperacion_tras_reinicio() {
    let (db, json, dir) = rutas("recovery");
    guardar_en(&scheduler_ejemplo(), &db, &json).unwrap();

    // "Reinicio": se carga desde disco y se aplica la política de recuperación
    let mut s = cargar_desde(&db, &json);
    let por_relanzar = s.recuperar_tras_reinicio();

    assert_eq!(por_relanzar, vec![5]); // solo el Queued se relanza
    assert_eq!(s.get_job(4).unwrap().get_state(), JobState::Failed(-1)); // el Running se marca fallido
    assert_eq!(s.get_job(5).unwrap().get_state(), JobState::Queued);

    // Los IDs no se reutilizan
    let nuevo = s.add_job("echo".into(), vec![]).get_id();
    assert_eq!(nuevo, 6);
    let _ = fs::remove_dir_all(dir);
}

#[test]
fn si_falta_sqlite_se_usa_json() {
    let (db, json, dir) = rutas("fallback_json");
    let original = scheduler_ejemplo();
    guardar_en(&original, &db, &json).unwrap();

    for ext in ["", "-wal", "-shm"] {
        let _ = fs::remove_file(format!("{}{}", db.display(), ext));
    }
    let cargado = cargar_desde(&db, &json);
    assert_eq!(texto(&original), texto(&cargado));
    let _ = fs::remove_dir_all(dir);
}

#[test]
fn si_sqlite_esta_corrupta_se_usa_json() {
    let (db, json, dir) = rutas("corrupta");
    let original = scheduler_ejemplo();
    guardar_en(&original, &db, &json).unwrap();

    for ext in ["-wal", "-shm"] {
        let _ = fs::remove_file(format!("{}{}", db.display(), ext));
    }
    fs::write(&db, b"esto no es una base de datos SQLite").unwrap();

    let cargado = cargar_desde(&db, &json);
    assert_eq!(texto(&original), texto(&cargado));
    let _ = fs::remove_dir_all(dir);
}

#[test]
fn sin_datos_previos_inicia_vacio() {
    let (db, json, dir) = rutas("vacio");
    let s = cargar_desde(&db, &json);
    assert!(s.pending_jobs().is_empty() && s.history_jobs().is_empty());
    assert_eq!(s.next_id(), 1);
    let _ = fs::remove_dir_all(dir);
}

#[test]
fn json_de_respaldo_es_legible() {
    let (db, json, dir) = rutas("legible");
    guardar_en(&scheduler_ejemplo(), &db, &json).unwrap();
    let contenido = fs::read_to_string(&json).unwrap();
    assert!(contenido.contains("\"program\": \"echo\""));
    assert!(!json.with_extension("json.tmp").exists()); // no quedan temporales
    let _ = fs::remove_dir_all(dir);
}

#[test]
fn concurrencia_sin_corrupcion_ni_ids_repetidos() {
    let (db, json, dir) = rutas("concurrencia");
    let sched = Arc::new(Mutex::new(Scheduler::new()));

    let hilos: Vec<_> = (0..8)
        .map(|h| {
            let sched = Arc::clone(&sched);
            let (db, json) = (db.clone(), json.clone());
            thread::spawn(move || {
                for i in 0..25 {
                    let mut s = sched.lock().unwrap();
                    let id = s.add_job("echo".into(), vec![format!("h{}-{}", h, i)]).get_id();
                    s.start_job(id);
                    s.complete_job(id, 0);
                    guardar_en(&s, &db, &json).unwrap();
                }
            })
        })
        .collect();
    for h in hilos {
        h.join().unwrap();
    }

    let cargado = cargar_desde(&db, &json);
    assert_eq!(cargado.history_jobs().len(), 200);
    let mut ids: Vec<u32> = cargado.history_jobs().iter().map(|j| j.get_id()).collect();
    ids.sort();
    ids.dedup();
    assert_eq!(ids.len(), 200); // sin IDs repetidos
    let _ = fs::remove_dir_all(dir);
}

#[test]
fn rendimiento_500_jobs() {
    let (db, json, dir) = rutas("rendimiento");
    let mut s = Scheduler::new();
    for i in 0..500 {
        let id = s.add_job("echo".into(), vec![i.to_string()]).get_id();
        s.start_job(id);
        s.complete_job(id, 0);
    }
    let t = Instant::now();
    guardar_en(&s, &db, &json).unwrap();
    let cargado = cargar_desde(&db, &json);
    let dur = t.elapsed();

    assert_eq!(cargado.history_jobs().len(), 500);
    assert!(dur.as_secs_f64() < 2.0, "tardó demasiado: {:?}", dur);
    println!("Guardar + cargar 500 jobs: {:?}", dur);
    let _ = fs::remove_dir_all(dir);
}

