//src/config.rs
// Configuración del servicio speedyG.

// Orden de precedencia (mayor -> menor)

use std::env;

// -- Valores por defecto --
pub const DEFAULT_QUEUE_CAP: usize = 3;
pub const DEFAULT_SPEEDYG_SOCKET: &str = "/tmp/speedyg.sock";
pub const DEFAULT_SPEEDYG_MAX_CURRENT: usize = 4;
pub const DEFAULT_SPEEDYG_GRACE_MS: u64 = 5_000;
pub const DEFAULT_SPEEDYG_DATA_DIR: &str = "/var/lib/speedyg";

// - struct de configuración en tiempo de ejecución -
#[derive(Debug, Clone)]
pub struct Config {
    //Ruta del socket Unix donde escucha el demonio.
    pub socket_path: String,
    //Capacidad máxima de la cola de jobs pendientes
    pub queue_cap: usize,
    // Número máximo de jobs concurrentes
    pub max_current: usize,
    // Tiempo de gracia antes de forzar el cierre al apagar el demonio.
    pub grace_ms: u64,
    // Directorio base para logs y datos persistentes
    pub data_dir: String,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            socket_path: DEFAULT_SPEEDYG_SOCKET.to_string(),
            queue_cap: DEFAULT_QUEUE_CAP,
            max_current: DEFAULT_SPEEDYG_MAX_CURRENT,
            grace_ms: DEFAULT_SPEEDYG_GRACE_MS,
            data_dir: DEFAULT_SPEEDYG_DATA_DIR.to_string(),
        }
    }
}

impl Config {
    pub fn from_env_and_args() -> Result<Self, String> {
        let mut cfg = Config::default();

        // Variables de entorno
        if let Ok(v) = env::var("SPEEDYG_SOCKET") {
            cfg.socket_path = v;
        }
        if let Ok(v) = env::var("SPEEDYG_QUEUE_CAP") {
            cfg.queue_cap = parse_usize("SPEEDYG_QUEUE_CAP", &v)?;
        }
        if let Ok(v) = env::var("SPEEDYG_MAX_CURRENT") {
            cfg.max_current = parse_usize("SPEEDYG_MAX_CURRENT", &v)?;
        }
        if let Ok(v) = env::var("SPEEDYG_GRACE_MS") {
            cfg.grace_ms = parse_u64("SPEEDYG_GRACE_MS", &v)?;
        }
        if let Ok(v) = env::var("SPEEDYG_DATA_DIR") {
            cfg.data_dir = v;
        }

        // - Flags CLI
        let args: Vec<String> = env::args().skip(1).collect();
        let mut i = 0;
        while i < args.len() {
            match args[i].as_str() {
                "--socket" => {
                    let val = next_arg(&args, i, "--socket")?;
                    cfg.socket_path = val.to_string();
                    i += 2;
                }
                "--queue-cap" => {
                    let val = next_arg(&args, i, "--queue-cap")?;
                    cfg.queue_cap = parse_usize("--queue-cap", val)?;
                    i += 2;
                }
                "--max-current" => {
                    let val = next_arg(&args, i, "--max-current")?;
                    cfg.max_current = parse_usize("--max-current", val)?;
                    i += 2;
                }
                "--grace-ms" => {
                    let val = next_arg(&args, i, "--grace-ms")?;
                    cfg.grace_ms = parse_u64("--grace-ms", val)?;
                    i += 2;
                }
                "--data-dir" => {
                    let val = next_arg(&args, i, "--data-dir")?;
                    cfg.data_dir = val.to_string();
                    i += 2;
                }
                _ => {
                    i += 1;
                }
            }
        }

        cfg.validate()?;
        Ok(cfg)
    }

    // Valida los valores finales; retorna un error si alguno es inválido.
    fn validate(&self) -> Result<(), String> {
        if self.socket_path.is_empty() {
            return Err("Config: 'socket' no puede estar vacío".to_string());
        }
        if self.queue_cap == 0 {
            return Err("Config: 'queue_cap' no puede ser cero".to_string());
        }
        if self.max_current == 0 {
            return Err("Config: 'max_current' no puede ser cero".to_string());
        }
        if self.grace_ms == 0 {
            return Err("Config: 'grace_ms' no puede ser cero".to_string());
        }
        if self.data_dir.is_empty() {
            return Err("Config: 'data_dir' no puede estar vacío".to_string());
        }
        Ok(())
    }
}

// Helpers de parseo
fn next_arg<'a>(args: &'a [String], i: usize, flag: &str) -> Result<&'a str, String> {
    args.get(i + 1)
        .map(|s| s.as_str())
        .ok_or_else(|| format!("Flag {} requiere un argumento", flag))
}

fn parse_usize(flag: &str, val: &str) -> Result<usize, String> {
    val 
        .parse::<usize>()
        .map_err(|_| format!("Config: '{}' requiere un número entero válido, se recibió '{}'", flag, val))
}

fn parse_u64(flag: &str, val: &str) -> Result<u64, String> {
    val 
        .parse::<u64>()
        .map_err(|_| format!("Config: '{}' requiere un número entero válido, se recibió '{}'", flag, val))
}
