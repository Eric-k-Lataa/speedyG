use crate::scheduler::Scheduler;
use serde_json;
use std::fs::{File, OpenOptions};
use std::io::{Read, Write};
use std::path::Path;

/// Ruta del archivo donde se guardará el estado del scheduler
const FILE_PATH: &str = "scheduler.json";

/// Guarda el estado actual del scheduler en un archivo JSON
pub fn guardar_scheduler(sched: &Scheduler) -> Result<(), std::io::Error> {
    let json = serde_json::to_string_pretty(sched)
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))?;

    let mut file = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .open(FILE_PATH)?;

    file.write_all(json.as_bytes())?;
    Ok(())
}

/// Carga el estado del scheduler desde un archivo JSON.
/// Si el archivo no existe o hay error, devuelve Err.
pub fn cargar_scheduler() -> Result<Scheduler, std::io::Error> {
    if !Path::new(FILE_PATH).exists() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::NotFound,
            "Archivo de scheduler no encontrado",
        ));
    }

    let mut file = File::open(FILE_PATH)?;
    let mut contents = String::new();
    file.read_to_string(&mut contents)?;

    let sched: Scheduler = serde_json::from_str(&contents)
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))?;

    Ok(sched)
}

