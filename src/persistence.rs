use crate::scheduler::Scheduler;
use crate::state_machine::{Job, JobState};
use rusqlite::{params, Connection, TransactionBehavior};
use std::collections::VecDeque;
use std::env;
use std::error::Error;
use std::fmt;
use std::fs::{self, File};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::Duration;
use tracing::{debug, error, info, warn};

const DB_POR_DEFECTO: &str = "speedyg.db";
const JSON_POR_DEFECTO: &str = "scheduler.json";

const ESQUEMA: &str = "
CREATE TABLE IF NOT EXISTS jobs (
    id         INTEGER PRIMARY KEY,
    program    TEXT    NOT NULL,
    args       TEXT    NOT NULL,                    -- arreglo JSON, ej. [\"hola\"]
    state      TEXT    NOT NULL CHECK (state IN ('Queued','Running','Succeeded','Failed','Canceled')),
    exit_code  INTEGER,
    location   TEXT    NOT NULL CHECK (location IN ('queue','history')),
    position   INTEGER NOT NULL,                    -- orden dentro de queue o history
    updated_at TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_jobs_state ON jobs(state);
CREATE TABLE IF NOT EXISTS meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
";


const UPSERT_JOB: &str = "
INSERT INTO jobs (id, program, args, state, exit_code, location, position)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
ON CONFLICT(id) DO UPDATE SET
    program    = excluded.program,
    args       = excluded.args,
    state      = excluded.state,
    exit_code  = excluded.exit_code,
    location   = excluded.location,
    position   = excluded.position,
    updated_at = datetime('now')
WHERE jobs.state     IS NOT excluded.state
   OR jobs.exit_code IS NOT excluded.exit_code
   OR jobs.location  IS NOT excluded.location
   OR jobs.position  IS NOT excluded.position
";



#[derive(Debug)]
pub enum PersistenceError {
    Io(std::io::Error),
    Json(serde_json::Error),
    Sqlite(rusqlite::Error),
    DatosInvalidos(String),
}

impl fmt::Display for PersistenceError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            PersistenceError::Io(e) => write!(f, "error de E/S: {}", e),
            PersistenceError::Json(e) => write!(f, "error de JSON: {}", e),
            PersistenceError::Sqlite(e) => write!(f, "error de SQLite: {}", e),
            PersistenceError::DatosInvalidos(m) => write!(f, "datos inválidos: {}", m),
        }
    }
}

impl Error for PersistenceError {}

impl From<std::io::Error> for PersistenceError {
    fn from(e: std::io::Error) -> Self {
        PersistenceError::Io(e)
    }
}
impl From<serde_json::Error> for PersistenceError {
    fn from(e: serde_json::Error) -> Self {
        PersistenceError::Json(e)
    }
}
impl From<rusqlite::Error> for PersistenceError {
    fn from(e: rusqlite::Error) -> Self {
        PersistenceError::Sqlite(e)
    }
}


fn ruta_db() -> PathBuf {
    env::var_os("SPEEDYG_DB")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(DB_POR_DEFECTO))
}

fn ruta_json() -> PathBuf {
    env::var_os("SPEEDYG_JSON")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(JSON_POR_DEFECTO))
}


pub fn guardar_scheduler(sched: &Scheduler) -> Result<(), PersistenceError> {
    guardar_en(sched, &ruta_db(), &ruta_json())
}


pub fn cargar_scheduler() -> Scheduler {
    cargar_desde(&ruta_db(), &ruta_json())
}



pub fn guardar_en(
    sched: &Scheduler,
    ruta_db: &Path,
    ruta_json: &Path,
) -> Result<(), PersistenceError> {
    guardar_sqlite(sched, ruta_db).map_err(|e| {
        error!("No se pudo guardar en SQLite ({}): {}", ruta_db.display(), e);
        e
    })?;

    if let Err(e) = guardar_json(sched, ruta_json) {
        warn!(
            "SQLite guardó bien, pero falló el respaldo JSON ({}): {}",
            ruta_json.display(),
            e
        );
    }

    debug!(
        "Persistencia OK: {} en cola, {} en historial, next_id={}",
        sched.pending_jobs().len(),
        sched.history_jobs().len(),
        sched.next_id()
    );
    Ok(())
}

/// Orden de carga: SQLite -> JSON -> Scheduler nuevo.
pub fn cargar_desde(ruta_db: &Path, ruta_json: &Path) -> Scheduler {
    match cargar_sqlite(ruta_db) {
        Ok(Some(sched)) => {
            info!(
                "Scheduler recuperado desde SQLite ({}): {} en cola, {} en historial",
                ruta_db.display(),
                sched.pending_jobs().len(),
                sched.history_jobs().len()
            );
            return sched;
        }
        Ok(None) => info!("SQLite sin datos previos; se intentará el respaldo JSON"),
        Err(e) => warn!("No se pudo leer SQLite ({}): {}; se intentará JSON", ruta_db.display(), e),
    }

    match cargar_json(ruta_json) {
        Ok(Some(sched)) => {
            info!(
                "Scheduler recuperado desde JSON ({}): {} en cola, {} en historial",
                ruta_json.display(),
                sched.pending_jobs().len(),
                sched.history_jobs().len()
            );
            sched
        }
        Ok(None) => {
            info!("No hay datos previos; se inicia un Scheduler vacío");
            Scheduler::new()
        }
        Err(e) => {
            error!("No se pudo leer el JSON ({}): {}; se inicia un Scheduler vacío", ruta_json.display(), e);
            Scheduler::new()
        }
    }
}

// SQLite

fn abrir_db(ruta: &Path) -> Result<Connection, PersistenceError> {
    let conn = Connection::open(ruta)?;
    
    conn.busy_timeout(Duration::from_secs(5))?;

    
    conn.pragma_update(None, "journal_mode", "WAL")?;
    conn.pragma_update(None, "synchronous", "FULL")?;
    conn.execute_batch(ESQUEMA)?;
    Ok(conn)
}

fn guardar_sqlite(sched: &Scheduler, ruta: &Path) -> Result<(), PersistenceError> {
    let mut conn = abrir_db(ruta)?;

    
    let tx = conn.transaction_with_behavior(TransactionBehavior::Immediate)?;
    {
        let mut stmt = tx.prepare_cached(UPSERT_JOB)?;
        for (pos, job) in sched.pending_jobs().into_iter().enumerate() {
            insertar_job(&mut stmt, job, "queue", pos)?;
        }
        for (pos, job) in sched.history_jobs().into_iter().enumerate() {
            insertar_job(&mut stmt, job, "history", pos)?;
        }
    }
    tx.execute(
        "INSERT INTO meta (key, value) VALUES ('next_id', ?1)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        params![sched.next_id().to_string()],
    )?;
    tx.commit()?;
    Ok(())
}

fn insertar_job(
    stmt: &mut rusqlite::CachedStatement<'_>,
    job: &Job,
    location: &str,
    position: usize,
) -> Result<(), PersistenceError> {
    let args_json = serde_json::to_string(job.get_args())?;
    stmt.execute(params![
        job.get_id(),
        job.get_program(),
        args_json,
        job.get_state().to_db(),
        job.get_exit_code(),
        location,
        position as i64,
    ])?;
    Ok(())
}

/// Ok(None) = la base existe pero aún no se ha guardado nada.
fn cargar_sqlite(ruta: &Path) -> Result<Option<Scheduler>, PersistenceError> {
    if !ruta.exists() {
        return Ok(None);
    }
    let conn = abrir_db(ruta)?;

    let next_meta: Option<String> = conn
        .query_row("SELECT value FROM meta WHERE key = 'next_id'", [], |r| r.get(0))
        .map(Some)
        .or_else(|e| match e {
            rusqlite::Error::QueryReturnedNoRows => Ok(None),
            otro => Err(otro),
        })?;
    let next_meta = match next_meta {
        Some(v) => v,
        None => return Ok(None),
    };
    let next_meta: u32 = next_meta
        .parse()
        .map_err(|_| PersistenceError::DatosInvalidos(format!("next_id inválido: {}", next_meta)))?;

    let mut stmt = conn.prepare(
        "SELECT id, program, args, state, exit_code, location
         FROM jobs ORDER BY position ASC, id ASC",
    )?;
    let filas = stmt
        .query_map([], |r| {
            Ok((
                r.get::<_, u32>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, String>(2)?,
                r.get::<_, String>(3)?,
                r.get::<_, Option<i32>>(4)?,
                r.get::<_, String>(5)?,
            ))
        })?
        .collect::<Result<Vec<_>, _>>()?;

    let mut queue = VecDeque::new();
    let mut history = Vec::new();
    let mut max_id = 0u32;

    for (id, program, args_json, state, exit_code, location) in filas {
        let args: Vec<String> = serde_json::from_str(&args_json)?;
        let state = JobState::from_db(&state, exit_code).ok_or_else(|| {
            PersistenceError::DatosInvalidos(format!("Job #{} con estado desconocido '{}'", id, state))
        })?;
        max_id = max_id.max(id);
        let job = Job::from_parts(id, program, args, state, exit_code);
        match location.as_str() {
            "queue" => queue.push_back(job),
            "history" => history.push(job),
            otra => {
                return Err(PersistenceError::DatosInvalidos(format!(
                    "Job #{} con ubicación desconocida '{}'",
                    id, otra
                )))
            }
        }
    }

    // Defensa extra: nunca reutilizar un ID aunque meta quedara desfasada.
    let next_id = next_meta.max(max_id + 1);
    Ok(Some(Scheduler::from_parts(next_id, queue, history)))
}



fn guardar_json(sched: &Scheduler, ruta: &Path) -> Result<(), PersistenceError> {
    let json = serde_json::to_string_pretty(sched)?;
    let tmp = ruta.with_extension("json.tmp");
    {
        let mut f = File::create(&tmp)?;
        f.write_all(json.as_bytes())?;
        f.sync_all()?;
    }
    fs::rename(&tmp, ruta)?;
    Ok(())
}

/// Ok(None) = el archivo no existe.
fn cargar_json(ruta: &Path) -> Result<Option<Scheduler>, PersistenceError> {
    if !ruta.exists() {
        return Ok(None);
    }
    let contenido = fs::read_to_string(ruta)?;
    Ok(Some(serde_json::from_str(&contenido)?))
}

