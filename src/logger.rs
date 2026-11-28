// src/logger.rs
// Bitácora estructurada de eventos operativos y errores (A2-12: RF-14, RF-23, RNF-15, RNF-22).

use chrono::Utc;
use serde::Serialize;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "UPPERCASE")]
pub enum LogLevel {
    Info,
    Warn,
    Error,
}

#[derive(Debug, Serialize)]
struct EventRecord<'a> {
    timestamp: String,
    level: LogLevel,
    event: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    request_id: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    job_id: Option<u32>,
    message: &'a str,
}

#[derive(Clone)]
pub struct EventLogger {
    file_path: PathBuf,
    write_lock: Arc<Mutex<()>>,
    req_counter: Arc<AtomicU64>,
}

impl EventLogger {
    /// Inicializa la bitácora dentro del directorio configurado (`data_dir/events.jsonl`).
    pub fn new(data_dir: &str) -> Result<Self, String> {
        let dir = Path::new(data_dir);
        fs::create_dir_all(dir).map_err(|e| {
            format!(
                "No se pudo crear directorio de bitácora {}: {}",
                data_dir, e
            )
        })?;

        let file_path = dir.join("events.jsonl");
        OpenOptions::new()
            .create(true)
            .append(true)
            .open(&file_path)
            .map_err(|e| {
                format!(
                    "No se pudo abrir archivo de bitácora {}: {}",
                    file_path.display(),
                    e
                )
            })?;

        Ok(Self {
            file_path,
            write_lock: Arc::new(Mutex::new(())),
            req_counter: Arc::new(AtomicU64::new(1)),
        })
    }

    /// Genera un identificador único de solicitud para correlación (RNF-22).
    pub fn next_request_id(&self) -> String {
        let id = self.req_counter.fetch_add(1, Ordering::Relaxed);
        format!("req-{}", id)
    }

    pub fn path(&self) -> &Path {
        &self.file_path
    }

    /// Escribe una línea JSONL en la bitácora sin exponer secretos ni configuración sensible (RNF-15).
    pub fn log(
        &self,
        level: LogLevel,
        event: &str,
        request_id: Option<&str>,
        job_id: Option<u32>,
        message: &str,
    ) {
        let record = EventRecord {
            timestamp: Utc::now().to_rfc3339(),
            level,
            event,
            request_id,
            job_id,
            message,
        };

        let Ok(mut line) = serde_json::to_string(&record) else {
            return;
        };
        line.push('\n');

        let _guard = self.write_lock.lock().unwrap_or_else(|e| e.into_inner());
        if let Ok(mut file) = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&self.file_path)
        {
            let _ = file.write_all(line.as_bytes());
            let _ = file.flush();
        }
    }

    pub fn info(&self, event: &str, request_id: Option<&str>, job_id: Option<u32>, message: &str) {
        self.log(LogLevel::Info, event, request_id, job_id, message);
    }

    pub fn warn(&self, event: &str, request_id: Option<&str>, job_id: Option<u32>, message: &str) {
        self.log(LogLevel::Warn, event, request_id, job_id, message);
    }

    pub fn error(&self, event: &str, request_id: Option<&str>, job_id: Option<u32>, message: &str) {
        self.log(LogLevel::Error, event, request_id, job_id, message);
    }
}
