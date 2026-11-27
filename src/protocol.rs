// src/protocol.rs

// Encabezado de versión y validación de compatibilidad del protocolo

pub const SERVER_MAJOR: u16 = 1;
pub const SERVER_MINOR: u16 = 0;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ProtocolVersion {
    pub major: u16,
    pub minor: u16,
}

impl ProtocolVersion {
    pub const fn new(major: u16, minor: u16) -> Self {
        Self { major, minor }
    }

    pub const fn current() -> Self {
        Self {
            major: SERVER_MAJOR,
            minor: SERVER_MINOR,
        }
    }

    pub fn parse(raw: &str) -> Result<Self, String> {
        let trimmed = raw.trim();
        let (major_str, minor_str) = trimmed.split_once('.').ok_or_else(|| {
            format!(
                "Versión incompatible '{}': se esperaba formato <major>.<minor>",
                trimmed
            )
        })?;

        let major = major_str
            .parse::<u16>()
            .map_err(|_| format!("Versión mayor incompatible en '{}'", trimmed))?;
        let minor = minor_str
            .parse::<u16>()
            .map_err(|_| format!("Versión menor incompatible en '{}'", trimmed))?;

        Ok(Self { major, minor })
    }
}

// Genera la línea de petición con el encabezado de versión actual del protocolo.
pub fn attach_version_header(payload: &str) -> String {
    let ver = ProtocolVersion::current();
    format!("v={}.{}|{}", ver.major, ver.minor, payload)
}

// Extrae el encabezado de versión, valida compatibilidad contra la versión actual y devuelve el payload limpio si es aceptado.
pub fn parse_and_validate_header(line: &str) -> Result<String, String> {
    let (header_part, payload) = line
        .split_once('|')
        .ok_or_else(|| "Encabezado de protocolo ausente o mal formado (se esperaba v=<major>.<minor>|<comando>)".to_string())?;

    let ver_str = header_part
        .strip_prefix("v=")
        .ok_or_else(|| format!("Encabezado inválido '{}': falta prefijo 'v='", header_part))?;

    let req_ver = ProtocolVersion::parse(ver_str)?;
    let current = ProtocolVersion::current();

    if req_ver.major != current.major {
        return Err(format!(
            "Versión mayor de protocolo incompatible ({}.{}). Versiones soportadas: {}.x (actual {}.{})",
            req_ver.major, req_ver.minor, current.major, current.major, current.minor
        ));
    }

    // Regla: aceptar versión menor igual o anterior dentro de la misma versión mayor.
    if req_ver.minor > current.minor {
        return Err(format!(
            "Versión menor de protocolo no soportada ({}.{}). Versiones soportadas: {}.0..{}.{}",
            req_ver.major, req_ver.minor, current.major, current.major, current.minor
        ));
    }

    Ok(payload.to_string())
}
