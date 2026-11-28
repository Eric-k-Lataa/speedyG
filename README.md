# speedyG

## Propósito

Desarrollar un sistema para Linux capaz de ejecutar, administrar, observar y controlar trabajos. El sistema funcionará localmente y permitirá operación remota dentro de una red privada.

"speedyG" es el nombre técnico de nuestra implementación de JobRunner.

## Integrantes

| Integrante | Correo institucional | Rol | Responsable principal |
|---|---|:---:|:---:|
| Binervia Huerta Diego Uriel | diego.binervia6698@alumnos.udg.mx | Low level Code | 🪲 |
| Consuelos Bonilla Andrea Carolina | andrea.consuelos5553@alumnos.udg.mx | State Manager | |
| Lopez Castillo Paola Guadalupe | paola.lopez1288@alumnos.udg.mx | Networking CLI & Backend | |
| Padilla Franco Erick Saul | erick.padilla5183@alumnos.udg.mx | DevOps | |

## Arquitectura

La arquitectura es un bucle de eventos que utiliza una máquina de estados finitos (FSM) para gestionar las operaciones del servicio y las transiciones del ciclo de vida de los trabajos.

Los estados de un trabajo son:

```
QUEUED ──► RUNNING ──► SUCCEEDED
   │           ├────► FAILED
   │           ├────► CANCELED
   │           └────► INTERRUPTED
   │
   └───────────────► CANCELED

```

Las decisiones arquitectónicas relevantes se documentan como ADR en [`docs/decisions/`](docs/decisions/README.md). Más detalle en la [guía técnica](docs/technical-guide/README.md) y la [guía de usuario](docs/user-guide/README.md). La [matriz de trazabilidad](verif/verification-plan/traceability-matrix.md) relaciona los requisitos con sus casos de verificación.

El estado `INTERRUPTED` identifica los trabajos que se encontraban en ejecución cuando el servicio se interrumpió y que son detectados durante el proceso de recuperación.

## Estructura del repositorio

```text
speedyG/
├── Cargo.toml
├── Cargo.lock
├── rust-toolchain.toml
├── Makefile
├── config.example.toml
├── README.md
├── src/
│   ├── bin/
│   │   └── speedyg.rs
│   ├── config.rs
│   ├── executor.rs
│   ├── lib.rs
│   ├── main.rs
│   ├── parser.rs
│   ├── persistence.rs
│   ├── protocol.rs
│   ├── scheduler.rs
│   ├── state_machine.rs
│   └── README.md
├── tests/
│   ├── executor_test.rs
│   ├── parser_test.rs
│   ├── persistence_test.rs
│   ├── protcol_test.rs
│   ├── scheduler_test.rs
│   └── state_machine_test.rs
├── docs/
│   ├── ai-usage/
│   ├── change-requests/
│   ├── decisions/
│   ├── incidents/
│   ├── technical-guide/
│   ├── user-guide/
│   ├── coding_standard.md
│   └── README.md
├── project-management/
│   ├── 01-minuta.md
│   ├── 02-minuta.md
│   ├── 03-minuta.md
│   ├── cronograma.md
│   ├── Matriz de roles.md
│   ├── risk register.md
│   └── README.md
└── verif/
    ├── scripts/
    │   ├── lib/
    │   ├── run-all.sh
    │   └── TC-*.sh
    ├── test-cases/
    │   ├── TC-*.md
    │   └── Template.md
    ├── test-data/
    ├── results/
    ├── verification-plan/
    │   ├── traceability-matrix.md
    │   └── verification-plan.md
    └── README.md
```

## Requisitos

- Linux (probado en Debian 13). Linux es la plataforma objetivo del proyecto, debido a su integración con sockets Unix y señales POSIX.
- `git`, `make`, `bash` y un compilador de C (`build-essential`), necesario para compilar SQLite embebido.
- Rust **1.98.1**. La versión está fijada en [`rust-toolchain.toml`](rust-toolchain.toml); con `rustup` se instala sola, junto con `rustfmt` y `clippy`.

```bash
sudo apt update
sudo apt install -y git make curl build-essential
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"
```

## Construcción

Desde un clon limpio:

```bash
git clone https://github.com/Eric-k-Lataa/speedyG
cd speedyG
make build
```

`make build` ejecuta `cargo build --release --locked` y produce dos binarios en `target/release/`:

| Binario | Función |
|---|---|
| `speedyG` | Demonio. Escucha en un socket Unix. |
| `speedyg` | Cliente CLI. Envía órdenes al demonio. |

`--locked` obliga a usar exactamente las versiones de [`Cargo.lock`](Cargo.lock), que está versionado.

### Comandos de `make`

| Comando | Qué hace |
|---|---|
| `make build` | Compila los binarios de entrega (release). |
| `make test` | Ejecuta las pruebas unitarias (`cargo test --locked`). |
| `make fmt` | Comprueba el formato (`cargo fmt --check`). |
| `make clippy` | Lint con `cargo clippy -- -D warnings`. |
| `make run-all` | Compila en debug y ejecuta los casos de verificación de `verif/`. |
| `make verify` | Todo lo anterior: `fmt`, `clippy`, `test` y `run-all`. |
| `make clean` | Borra `target/`. |

`target/` no se versiona. Los binarios y demás artefactos de compilación se generan siempre localmente.

## Ejecución

Se necesitan dos terminales, ambas en el directorio del proyecto.

**Terminal 1. Demonio:**

```bash
./target/release/speedyG
```

Debe mostrar: `Demonio speedyG escuchando en /tmp/speedyg.sock`.

**Terminal 2. Cliente:**

```bash
./target/release/speedyg health        # comprueba que el demonio responde
./target/release/speedyg help          # comandos disponibles
./target/release/speedyg echo hola     # envía un trabajo
./target/release/speedyg sleep 10      # envía un trabajo de larga duración
./target/release/speedyg status        # lista todos los trabajos
./target/release/speedyg status <ID>   # estado de un trabajo
./target/release/speedyg cancel <ID>   # solicita la cancelación de un trabajo
```

Durante el desarrollo también se puede usar `cargo run --bin speedyG` y `cargo run --bin speedyg -- <comando>`.

### Configuración

El demonio se configura con variables de entorno o flags. Todos los parámetros, sus valores por defecto y ejemplos están en [`config.example.toml`](config.example.toml). El cliente acepta `--socket <ruta>` o `SPEEDYG_SOCKET`.

## Pruebas y verificación

- Pruebas unitarias: `make test`.
- Casos de verificación (TC): `make run-all`, o individualmente `bash verif/scripts/TC-001.sh`. Los scripts requieren que los binarios de `target/debug` estén compilados, y `make run-all` ya se encarga de eso.
- Verificación completa antes de entregar: `make verify`.
- Los resultados se guardan en `verif/results/`.

El CI ([`rust-ci.yml`](.github/workflows/rust-ci.yml)) ejecuta `fmt`, `clippy -D warnings`, `build`, `test` y `run-all` con los mismos comandos de `make`.

## Dependencias

Todas las dependencias directas están en [`Cargo.toml`](Cargo.toml) y sus versiones exactas en `Cargo.lock`.

| Crate | Uso en el proyecto |
|---|---|
| `tokio` (`full`) | Runtime asíncrono: socket Unix del demonio, ejecución de procesos en segundo plano, temporizadores y manejo de señales. |
| `tracing` | Mensajes de registro (logs) estructurados del demonio. |
| `tracing-subscriber` | Formateo y salida de los logs de `tracing`. |
| `serde` (`derive`) | Serialización de las estructuras de trabajos y del planificador. |
| `serde_json` | Formato JSON para guardar los argumentos de los trabajos y la instantánea del planificador. |
| `rusqlite` (`bundled`) | Persistencia en SQLite ([ADR-03](docs/decisions/ADR-03-persistence.md)). `bundled` compila SQLite dentro del binario y evita depender de una librería del sistema. |
| `chrono` (`serde`) | Marcas de tiempo UTC de recepción, inicio y fin de cada trabajo. |
| `nix` (`process`, `signal`) | Envío de señales a procesos y grupos de procesos para cancelar trabajos. |

## Versiones y entregas

- La versión del paquete en `Cargo.toml` coincide con la etiqueta de git sin la `v`.
- `v1.0.0-rc1`: etiqueta anotada en el candidato a entrega.
- `v1.0.0`: etiqueta anotada en la entrega final.
- Cada etiqueta apunta a un commit inmutable. Si hay que corregir algo, se crea una etiqueta nueva (`v1.0.0-rc2`) y no se mueve la anterior.

```bash
git tag -a v1.0.0-rc1 -m "speedyG v1.0.0-rc1"
git push origin v1.0.0-rc1
```

## Estado del proyecto

- Estructura base: `Cargo.toml`, `Cargo.lock`, `rust-toolchain.toml`, `Makefile`, `src/`, `tests/`, `verif/`, `docs/`, `project-management/`.
- Módulos en `src/`: `main.rs`, `lib.rs`, `parser.rs`, `persistence.rs`, `state_machine.rs`, `scheduler.rs`, `executor.rs`, `config.rs`.
- ADR documentados: lenguaje, arquitectura, persistencia, cancelación/escalamiento/duplicados/saturación, concurrencia, protocolo de red, retención de resultados y limite de recursos (ver [`docs/decisions/`](docs/decisions/README.md)).
- Se implementaron la ejecución y administración de trabajos mediante una máquina de estados, con cola FIFO, límite de trabajos en espera, concurrencia máxima, manejo de solicitudes duplicadas y cancelación con escalamiento de señales (`SIGTERM` y `SIGKILL`).
- Se implementaron el protocolo de comunicación, el versionado, la delimitación de mensajes, los límites de tamaño de solicitudes, las consultas de salud, las respuestas de error y los mecanismos de conexión mediante sockets Unix y TCP definidos para el servicio.
- Se implementaron la captura y retención limitada de salidas, el límite del historial de trabajos, la persistencia en SQLite con respaldo JSON, la recuperación tras reinicios y el cierre controlado del servicio.
- Se cuenta con pruebas unitarias y casos de verificación para validar el funcionamiento de los componentes y los requisitos del sistema.
