// src/config.rs
// Configuración del servicio speedyG.

// Orden de precedencia (mayor -> menor):
// 1. Flags CLI
// 2. Variables de entorno SPEEDYG_*
// 3. Valores por defecto

use std::env;
use std::net::IpAddr;

// -- Valores por defecto --
pub const DEFAULT_QUEUE_CAP: usize = 3;
pub const DEFAULT_SPEEDYG_SOCKET: &str = "/tmp/speedyg.sock";
pub const DEFAULT_SPEEDYG_MAX_CURRENT: usize = 3;
pub const DEFAULT_SPEEDYG_GRACE_MS: u64 = 5_000;
pub const DEFAULT_SPEEDYG_DATA_DIR: &str = "/tmp/speedyg-data";
pub const DEFAULT_MAX_MESSAGE_BYTES: usize = 65536;
pub const DEFAULT_MAX_ARGUMENTS: usize = 32;
pub const DEFAULT_MAX_ARGUMENT_BYTES: usize = 256;
pub const DEFAULT_MAX_OUTPUT_BYTES: usize = 1_000_000;
pub const DEFAULT_MAX_COMPLETED_JOBS: usize = 1000;

pub const DEFAULT_SPEEDYG_TCP_ENABLED: bool = true;
pub const DEFAULT_SPEEDYG_TCP_HOST: &str = "127.0.0.1";
pub const DEFAULT_SPEEDYG_TCP_PORT: u16 = 7878;

// - struct de configuración en tiempo de ejecución -
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Config {
    // Ruta del socket Unix donde escucha el demonio.
    pub socket_path: String,
    // Capacidad máxima de la cola de jobs pendientes
    pub queue_cap: usize,
    // Número máximo de jobs concurrentes
    pub max_current: usize,
    // Tiempo de gracia antes de forzar el cierre al apagar el demonio.
    pub grace_ms: u64,
    // Directorio base para logs y datos persistentes
    pub data_dir: String,
    // Habilita o deshabilita el listener TCP
    pub tcp_enabled: bool,
    // Dirección IP donde escucha el listener TCP (por defecto 127.0.0.1)
    pub tcp_host: String,
    // Puerto donde escucha el listener TCP
    pub tcp_port: u16,
    // Lista blanca de IPs permitidas cuando tcp_host no es loopback (A3-09)
    pub tcp_allowlist: Vec<IpAddr>,
    // Número máximo de bytes permitiddos por mensaje
    pub max_message_bytes: usize,
    // Número máximo de argumentos permitidos por comando
    pub max_arguments: usize,
    // Número máximo de bytes permitidos por argumento
    pub max_argument_bytes: usize,
    // Número máximo de bytes de salida almacenados por trabajo
    pub max_output_bytes: usize,
    // Número máximo de trabajos terminados conservados en el historial
    pub max_completed_jobs: usize,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            socket_path: DEFAULT_SPEEDYG_SOCKET.to_string(),
            queue_cap: DEFAULT_QUEUE_CAP,
            max_current: DEFAULT_SPEEDYG_MAX_CURRENT,
            grace_ms: DEFAULT_SPEEDYG_GRACE_MS,
            data_dir: DEFAULT_SPEEDYG_DATA_DIR.to_string(),
            tcp_enabled: DEFAULT_SPEEDYG_TCP_ENABLED,
            tcp_host: DEFAULT_SPEEDYG_TCP_HOST.to_string(),
            tcp_port: DEFAULT_SPEEDYG_TCP_PORT,
            tcp_allowlist: Vec::new(),
            max_message_bytes: DEFAULT_MAX_MESSAGE_BYTES,
            max_arguments: DEFAULT_MAX_ARGUMENTS,
            max_argument_bytes: DEFAULT_MAX_ARGUMENT_BYTES,
            max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES,
            max_completed_jobs: DEFAULT_MAX_COMPLETED_JOBS,
        }
    }
}

impl Config {
    pub fn from_env_and_args() -> Result<Self, String> {
        let args: Vec<String> = env::args().skip(1).collect();
        Self::from_iter_env_and_args(|k| env::var(k), &args)
    }

    pub fn from_iter_env_and_args<F>(get_env: F, args: &[String]) -> Result<Self, String>
    where
        F: Fn(&str) -> Result<String, env::VarError>,
    {
        let mut cfg = Config::default();

        // 1. Variables de entorno
        if let Ok(v) = get_env("SPEEDYG_SOCKET") {
            cfg.socket_path = v;
        }
        if let Ok(v) = get_env("SPEEDYG_QUEUE_CAP") {
            cfg.queue_cap = parse_usize("SPEEDYG_QUEUE_CAP", &v)?;
        }
        if let Ok(v) = get_env("SPEEDYG_MAX_CURRENT") {
            cfg.max_current = parse_usize("SPEEDYG_MAX_CURRENT", &v)?;
        }
        if let Ok(v) = get_env("SPEEDYG_GRACE_MS") {
            cfg.grace_ms = parse_u64("SPEEDYG_GRACE_MS", &v)?;
        }
        if let Ok(v) = get_env("SPEEDYG_DATA_DIR") {
            cfg.data_dir = v;
        }
        if let Ok(v) = get_env("SPEEDYG_TCP_ENABLED") {
            cfg.tcp_enabled = parse_bool("SPEEDYG_TCP_ENABLED", &v)?;
        }
        if let Ok(v) = get_env("SPEEDYG_TCP_HOST") {
            cfg.tcp_host = v;
        }
        if let Ok(v) = get_env("SPEEDYG_TCP_PORT") {
            cfg.tcp_port = parse_u16("SPEEDYG_TCP_PORT", &v)?;
        }
        if let Ok(v) = get_env("SPEEDYG_TCP_ALLOWLIST") {
            cfg.tcp_allowlist = parse_ip_list("SPEEDYG_TCP_ALLOWLIST", &v)?;
        }
        if let Ok(v) = get_env("SPEEDYG_MAX_MESSAGE_BYTES") {
            cfg.max_message_bytes = parse_usize("SPEEDYG_MAX_MESSAGE_BYTES", &v)?;
        }
        if let Ok(v) = get_env("SPEEDYG_MAX_ARGUMENTS") {
            cfg.max_arguments = parse_usize("SPEEDYG_MAX_ARGUMENTS", &v)?;
        }
        if let Ok(v) = get_env("SPEEDYG_MAX_ARGUMENT_BYTES") {
            cfg.max_argument_bytes = parse_usize("SPEEDYG_MAX_ARGUMENT_BYTES", &v)?;
        }
        if let Ok(v) = get_env("SPEEDYG_MAX_OUTPUT_BYTES") {
            cfg.max_output_bytes = parse_usize("SPEEDYG_MAX_OUTPUT_BYTES", &v)?;
        }
        if let Ok(v) = get_env("SPEEDYG_MAX_COMPLETED_JOBS") {
            cfg.max_completed_jobs = parse_usize("SPEEDYG_MAX_COMPLETED_JOBS", &v)?;
        }

        // 2. Flags CLI (mayor precedencia)
        let mut i = 0;
        while i < args.len() {
            match args[i].as_str() {
                "--socket" => {
                    let val = next_arg(args, i, "--socket")?;
                    cfg.socket_path = val.to_string();
                    i += 2;
                }
                "--queue-cap" => {
                    let val = next_arg(args, i, "--queue-cap")?;
                    cfg.queue_cap = parse_usize("--queue-cap", val)?;
                    i += 2;
                }
                "--max-current" => {
                    let val = next_arg(args, i, "--max-current")?;
                    cfg.max_current = parse_usize("--max-current", val)?;
                    i += 2;
                }
                "--grace-ms" => {
                    let val = next_arg(args, i, "--grace-ms")?;
                    cfg.grace_ms = parse_u64("--grace-ms", val)?;
                    i += 2;
                }
                "--data-dir" => {
                    let val = next_arg(args, i, "--data-dir")?;
                    cfg.data_dir = val.to_string();
                    i += 2;
                }
                "--tcp-enabled" => {
                    let val = next_arg(args, i, "--tcp-enabled")?;
                    cfg.tcp_enabled = parse_bool("--tcp-enabled", val)?;
                    i += 2;
                }
                "--disable-tcp" => {
                    cfg.tcp_enabled = false;
                    i += 1;
                }
                "--tcp-host" => {
                    let val = next_arg(args, i, "--tcp-host")?;
                    cfg.tcp_host = val.to_string();
                    i += 2;
                }
                "--tcp-port" => {
                    let val = next_arg(args, i, "--tcp-port")?;
                    cfg.tcp_port = parse_u16("--tcp-port", val)?;
                    i += 2;
                }
                "--tcp-allowlist" => {
                    let val = next_arg(args, i, "--tcp-allowlist")?;
                    cfg.tcp_allowlist = parse_ip_list("--tcp-allowlist", val)?;
                    i += 2;
                }
                "--max-message-bytes" => {
                    let val = next_arg(args, i, "--max-message-bytes")?;
                    cfg.max_message_bytes = parse_usize("--max-message-bytes", val)?;
                    i += 2;
                }
                "--max-arguments" => {
                    let val = next_arg(args, i, "--max-arguments")?;
                    cfg.max_arguments = parse_usize("--max-arguments", val)?;
                    i += 2;
                }
                "--max-argument-bytes" => {
                    let val = next_arg(args, i, "--max-argument-bytes")?;
                    cfg.max_argument_bytes = parse_usize("--max-argument-bytes", val)?;
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

    pub fn tcp_addr(&self) -> String {
        format!("{}:{}", self.tcp_host, self.tcp_port)
    }

    // Valida los valores finales; retorna un error si alguno es inválido.
    pub fn validate(&self) -> Result<(), String> {
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

        if self.tcp_enabled {
            if self.tcp_port == 0 {
                return Err("Config: 'tcp_port' no puede ser cero".to_string());
            }

            let ip: IpAddr = self.tcp_host.parse().map_err(|_| {
                format!(
                    "Config: 'tcp_host' debe ser una dirección IP válida, se recibió '{}'",
                    self.tcp_host
                )
            })?;

            // RNF-12 / A3-09: prohibido escuchar en 0.0.0.0 o IPs no-loopback sin allow-list
            if !ip.is_loopback() && self.tcp_allowlist.is_empty() {
                return Err(format!(
                    "Config: 'tcp_host' ({}) no es loopback y requiere una allow-list configurada (A3-09)",
                    ip
                ));
            }
        }

        if self.max_message_bytes == 0 {
            return Err("Config: 'max_message_bytes' no puede ser cero".to_string());
        }
        if self.max_arguments == 0 {
            return Err("Config: 'max_arguments' no puede ser cero".to_string());
        }
        if self.max_argument_bytes == 0 {
            return Err("Config: 'max_argument_bytes' no puede ser cero".to_string());
        }
        if self.max_output_bytes == 0 {
            return Err("Config: 'max_output_bytes' no puede ser cero".to_string());
        }
        if self.max_completed_jobs == 0 {
            return Err("Config: 'max_completed_jobs' no puede ser cero".to_string());
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
    val.parse::<usize>().map_err(|_| {
        format!(
            "Config: '{}' requiere un número entero válido, se recibió '{}'",
            flag, val
        )
    })
}

fn parse_u64(flag: &str, val: &str) -> Result<u64, String> {
    val.parse::<u64>().map_err(|_| {
        format!(
            "Config: '{}' requiere un número entero válido, se recibió '{}'",
            flag, val
        )
    })
}

fn parse_u16(flag: &str, val: &str) -> Result<u16, String> {
    val.parse::<u16>().map_err(|_| {
        format!(
            "Config: '{}' requiere un puerto válido (1-65535), se recibió '{}'",
            flag, val
        )
    })
}

fn parse_bool(flag: &str, val: &str) -> Result<bool, String> {
    match val.trim().to_ascii_lowercase().as_str() {
        "1" | "true" | "yes" | "on" => Ok(true),
        "0" | "false" | "no" | "off" => Ok(false),
        _ => Err(format!(
            "Config: '{}' requiere un booleano válido (true/false/1/0), se recibió '{}'",
            flag, val
        )),
    }
}

fn parse_ip_list(flag: &str, val: &str) -> Result<Vec<IpAddr>, String> {
    if val.trim().is_empty() {
        return Ok(Vec::new());
    }
    val.split(',')
        .map(|raw| {
            let trimmed = raw.trim();
            if trimmed.is_empty() {
                return Err(format!(
                    "Config: '{}' contiene una entrada vacía en la lista de IPs",
                    flag
                ));
            }
            trimmed
                .parse::<IpAddr>()
                .map_err(|_| format!("Config: '{}' contiene una IP inválida '{}'", flag, trimmed))
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn empty_env(_: &str) -> Result<String, env::VarError> {
        Err(env::VarError::NotPresent)
    }

    #[test]
    fn defaults_bind_loopback_tcp() {
        let cfg = Config::from_iter_env_and_args(empty_env, &[]).unwrap();
        assert!(cfg.tcp_enabled);
        assert_eq!(cfg.tcp_host, "127.0.0.1");
        assert_eq!(cfg.tcp_port, 7878);
        assert!(cfg.tcp_allowlist.is_empty());
    }

    #[test]
    fn rejects_unspecified_or_public_ip_without_allowlist() {
        let args_zero = vec!["--tcp-host".to_string(), "0.0.0.0".to_string()];
        let err_zero = Config::from_iter_env_and_args(empty_env, &args_zero).unwrap_err();
        assert!(err_zero.contains("allow-list"));

        let args_pub = vec!["--tcp-host".to_string(), "198.51.100.25".to_string()];
        let err_pub = Config::from_iter_env_and_args(empty_env, &args_pub).unwrap_err();
        assert!(err_pub.contains("allow-list"));
    }

    #[test]
    fn allows_non_loopback_with_allowlist() {
        let args = vec![
            "--tcp-host".to_string(),
            "0.0.0.0".to_string(),
            "--tcp-allowlist".to_string(),
            "192.168.1.10,10.0.0.2".to_string(),
        ];
        let cfg = Config::from_iter_env_and_args(empty_env, &args).unwrap();
        assert_eq!(cfg.tcp_host, "0.0.0.0");
        assert_eq!(cfg.tcp_allowlist.len(), 2);
    }

    #[test]
    fn cli_overrides_env_and_supports_disable_tcp() {
        let env_fn = |k: &str| match k {
            "SPEEDYG_TCP_HOST" => Ok("127.0.0.1".to_string()),
            "SPEEDYG_TCP_PORT" => Ok("8080".to_string()),
            _ => Err(env::VarError::NotPresent),
        };
        let args = vec![
            "--tcp-port".to_string(),
            "9090".to_string(),
            "--disable-tcp".to_string(),
        ];
        let cfg = Config::from_iter_env_and_args(env_fn, &args).unwrap();
        assert!(!cfg.tcp_enabled);
        assert_eq!(cfg.tcp_port, 9090);
    }

    #[test]
    fn rejects_invalid_port_or_ip() {
        let bad_port = vec!["--tcp-port".to_string(), "0".to_string()];
        assert!(Config::from_iter_env_and_args(empty_env, &bad_port).is_err());

        let bad_ip = vec!["--tcp-host".to_string(), "not-an-ip".to_string()];
        assert!(Config::from_iter_env_and_args(empty_env, &bad_ip).is_err());
    }
}
