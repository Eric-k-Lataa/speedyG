# speedyG

## Propósito

Desarrollar un sistema para Linux capaz de ejecutar, administrar, observar y controlar trabajos. El sistema funcionará localmente y permitirá operación remota dentro de una red privada.

"speedyG" será el nombre técnico de nuestra implementacion de JobRunner.


## Integrantes

| Integrante |   Correo institucional  |  Rol  | Responsable principal|
|------------|-------------------------|:-------:|:----------------------:
|Binervia Huerta Diego Uriel       |diego.binervia6698@alumnos.udg.mx                         |Low level Code       | ✓ |
|Consuelos Bonilla Andrea Carolina            | andrea.consuelos5553@alumnos.udg.mx                         |State Manager       |
|Lopez Castillo Paola Guadalupe            |paola.lopez1288@alumnos.udg.mx                        |Networking CLI & Backend       |
|Padilla Franco Erick Saul            |erick.padilla5183@alumnos.udg.mx                         |DevOps       |


## Construcción provisional
### Arquitectura

La arquitectura propuesta es un bucle de eventos que utiliza una máquina de estados finitos (FSM) para gestionar las operaciones del servicio y las transiciones del ciclo de vida de los trabajos.

Las decisiones arquitectónicas relevantes serán documentadas mediante Arhitecture Desicion Records (ADR).

Los estados considerados para un trabajo son:
```
QUEUED → RUNNING → SUCCEEDED
                ├→ FAILED
                └→ CANCELED
```
La arquitectura deberá permitir gestionar trabajos locales y solicitudes remotas, manteniendo un comportamiento consistente ante concurrencia, cancelaciones, errores y desconexiones.

## Construcción y Ejecución

- SpeedyG se trabaja sobre Debian 13
- Para este proyecto es necesaria la instalación de Rust (1.98.1) y Cargo (1.98.1)
- El uso de la herramienta *cargo fmt* para dar formato al código.
- La herramienta *cargo clippy* para verificar el código por errores básicos y detener la compilación del proyecto en caso de warnings.

Este proyecto se compone de dos partes:
- speedyG es el demonio que escucha en el socket. Comando: *cargo run --bin speedyG*
- speedyg envía una orden al demonio. Comando: *cargo run --bin speedyg <comando>*

### Dependencias del proyecto

- *tokio:* Para la ejecución de tareas en segundo plano y ejecución de comandos.
- *serde:* Convertir las estructuras a un formato guardable.
- *serde_json:* Guardar y leer.
- *tracing* y *tracing_subscriber* : Mensajes de registro (logs) de speedyG.

### Primeros pasos

- Clonar el repositorio con el comando:
  
  git clone https://github.com/Eric-k-Lataa/speedyG
  cd speedyG
  
- Instalar dependencias del sistema y Rust:
  
  sudo apt update
  sudo apt install -y git curl build-essential
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
  source "$HOME/.cargo/env"
  
- Verificar la instalación:
  
  rustc --version
  cargo --version

- Instalar las herramientas de formato y revisión:
  
  rustup component add clippy rustfmt
  
- Compilar: Utilizamos los siguiente comandos:
  
  *cargo check* para revisar que el código compila sin generar un ejecutable.
  *cargo build* para compilar el programa.

### Ejecución

Para ejecutar el proyecto es necesario el uso de dos terminales, ambas dentro del directorio del proyecto.

Terminal 1. Iniciar el demonio
- Comando: cargo run -- bin speedyG
  
  Debe mostrar el mensaje : Demonio speedyG escuchando en /tmp/speedyg.sock

Terminal 2. El cliente:
- Comando: *cargo run --bin speedyg -- health*

  Comprobar si el demonio responde.
  
- Comando: *cargo run --bin speedyg -- help*

  Se utiliza para ver los comandos disponibles.
  
- Comando: *cargo run --bin speedyg -- status*

  Lista todos los trabajos.
  
- Comando: *cargo run --bin speedyg -- echo name*

  Enviar un trabajo.
  
- Comando: *cargo run --bin speedyg -- sleep 10*

  Envía un trabajo de larga duración.
  
- Comando: *cargo run --bin speedyg -- cancel <ID>*

  Solicitar la cancelación de un trabajo.
  
- Comando: *cargo run --bin speedyg -- status <ID>*

  Consultar el estado de un trabajo.

### Pruebas
-  Comando: *cargo test*

   Ejecuta las pruebas automatizadas del proyecto.

- Pruebas manuales:  *verif/scripts/TC-001.sh*

Su objetivo principal es verificar que el servicio en segundo plano (el daemon) pueda iniciar, aceptar solicitudes del cliente mediante un socket, gestionar correctamente el ciclo de vida de los trabajos (jobs), validar comandos de seguridad y mantenerse estable ante errores.
  
Para realizar una prueba manual sobre el proyecto es necesario que el demonio speedyG este escuchando.

Realiza 7 pruebas distintas, y si se logran marca PASS.
  

## Estado del proyecto

Estado actual:

- Estructura base del proyecto speedyG:
  - speedyG : *Cargo.lock, Cargo.toml, docs, project-management, Readme.md, src, target, tests, verif*
  - /src/ ls : *main.rs, lib.rs, parser.rs.persistence.rs, state_machine.rs, scheduler.rs, executor.rs*
  
- El desarrollo de los ADR iniciales : (ADR-01-Lenguaje, ADR-02-Arquitectura, ADR-03-Persistencia).
- Implementación de requisitos solicitados en la actividad 00.
- Se establecieron unas normativas de control para el manejo de errores y señales.
- Actualmente cada uno de los integrantes trabaja en los Issues asignados.
- Se elaboraron pruebas de ejecución, consulta y finalización de trabajos.

Próximos pasos: 
- Concurrencia, persistencia y robustez.
- Cancelación de trabajos en cola y ejecución.
- ADR de concurrencia, persistencia, recuperación y cancelación.
