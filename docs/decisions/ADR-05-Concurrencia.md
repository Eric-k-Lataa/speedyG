# ADR-05: Modelo de Concurrencia, Estado Compartido y Gestión de Procesos Hijos

## Contexto
ADR-02 definió la arquitectura base basada en Event Loop y FSM. Para concretar la implementación en Rust sobre Linux, se requiere definir la estrategia de acceso al estado compartido (cola y tabla de trabajos) y el mecanismo para lanzar, supervisar y cancelar procesos hijos sin introducir estados inconsistentes ni procesos zombi.

Actualmente, cada conexión entrante se atiende en una tarea dedicada (`tokio::spawn`). La implementación previa del ejecutor utilizaba `std::process::Command::output()`, la cual bloqueaba hasta la finalización del hijo y no exponía su identificador de proceso (PID) ni su grupo de procesos (PGID). Esto impedía la cancelación en tiempo real y generaba inconsistencias donde un trabajo figuraba como cancelado en la FSM pero su proceso continuaba en ejecución en el sistema operativo.

## Alternativas consideradas

### Estrategias de Estado Compartido

#### Alternativa 1. Estado compartido con `std::sync::Mutex` (`Arc<Mutex<Scheduler>>`)
**Ventajas:**
* Simplicidad en el razonamiento del código: las operaciones sobre la cola y la tabla de trabajos ejecutan como secciones críticas síncronas e indivisibles.
* Integración directa con las estructuras existentes sin requerir una reescritura total del flujo de solicitudes.
* Garantías del compilador: el guardián del bloqueo (`MutexGuard`) de la biblioteca estándar no implementa `Send`, lo que impide por diseño retener el bloqueo a través de puntos de suspensión (`.await`) dentro del runtime de Tokio.

**Desventajas:**
* Dependencia estricta de la disciplina de desarrollo para no realizar operaciones de E/S lentas o bloqueantes con el candado tomado.
* Riesgo de envenenamiento del candado (`poisoned lock`) si un hilo entra en pánico durante la ejecución de la sección crítica.

#### Alternativa 2. Estado compartido con `tokio::sync::Mutex`
**Ventajas:**
* Permite mantener la referencia al bloqueo a través de puntos de suspensión (`.await`) en código asíncrono.

**Desventajas:**
* Incurre en un costo de sobrecarga superior a `std::sync::Mutex` para secciones críticas exclusivamente síncronas y de corta duración.
* Fomenta el patrón anti-patrón de retener bloqueos de estado durante operaciones de E/S o espera de procesos, serializando las peticiones concurrentes del servicio.

#### Alternativa 3. Tarea única propietaria del estado y comunicación vía canales MPSC (Modelo de Actores)
**Ventajas:**
* Eliminación total de bloqueos explícitos: la cola y la FSM residen exclusivamente en una tarea dedicada.
* Garantía estructural contra condiciones de carrera sobre el estado interno.

**Desventajas:**
* Mayor complejidad de implementación: cada consulta o modificación requiere enviar un mensaje y esperar una respuesta por un canal `oneshot`.
* La tarea central representa un punto único de falla y cuello de botella si se bloquea procesando una petición.
* Reescritura profunda del código a una etapa avanzada del desarrollo del proyecto.

---

### Mecanismos de Creación y Control de Procesos Hijos

#### Opción 1. Uso de `tokio::process::Command` con asignación de grupo de procesos (`process_group(0)`)
**Ventajas:**
* Integración nativa con el bucle de eventos de Tokio; la espera de los procesos no bloquea hilos del sistema.
* Asignación de un PGID propio por trabajo, permitiendo enviar señales (`SIGTERM`/`SIGKILL`) al grupo completo de procesos descendientes (`killpg`).

**Desventajas:**
* Procesos descendientes que invoquen la llamada del sistema `setsid()` escapan al control del grupo de procesos.

#### Opción 2. Ejecución síncrona vía `std::process::Command` con hilos dedicados por trabajo
**Ventajas:**
* Control explícito de la ejecución utilizando únicamente la biblioteca estándar.

**Desventajas:**
* Agotamiento de hilos del sistema bajo escenarios de alta concurrencia al mantener un hilo bloqueado por cada trabajo activo.
* Mezcla de dos modelos de concurrencia opuestos (hilos síncronos y ejecutor asíncrono) dentro de la misma aplicación.

#### Opción 3. Creación manual de procesos mediante `fork`/`exec` con identificadores `pidfd`
**Ventajas:**
* Uso de `pidfd_open` para evitar condiciones de carrera por reutilización de PIDs en el kernel de Linux e integración directa con `epoll`.

**Desventajas:**
* Requiere bloques de código no seguro (`unsafe`) y llamadas nativas a la C library (`libc`/`nix`).
* Dependencia de versiones de Linux Kernel >= 5.3 y soporte inestable en Rust estándar.

## Decisión
Se selecciona la **Alternativa 1 (`std::sync::Mutex`)** para la gestión del estado compartido en combinación con la **Opción 1 (`tokio::process::Command` con PGID)** para la gestión de procesos.

El estado del `Scheduler` reside tras un `std::sync::Mutex` síncrono. La sección crítica se limita estrictamente a la validación de transiciones en la FSM y la manipulación de estructuras en memoria. La comunicación del estado de los procesos hacia el `Scheduler` se realiza mediante un canal asíncrono MPSC.

Cada trabajo en ejecución es administrado por un **supervisor asíncrono dedicado** (`tokio::spawn`) que posee la propiedad exclusiva de la estructura `Child`, se encarga del envío de señales al PGID y ejecuta siempre la llamada `wait()` para recolectar el estado de salida.

## Consecuencias

### Estrategias de Estado Compartido

#### Alternativa 1. `std::sync::Mutex` (Seleccionada)
**Positivas:**
* Implementación simple y predecible; previene de forma estática la retención del bloqueo en puntos de suspensión `.await`.
* Transiciones de la FSM ejecutadas en operaciones atómicas breves.

**Negativas:**
* Requiere apego estricto a las reglas de codificación internas (R1-R6) para evitar secciones críticas prolongada.

**Riesgos:**
* Inserción inadvertida de operaciones de E/S dentro de la sección crítica. Se mitiga mediante análisis estático y reglas en la revisión de código.
* Envenenamiento del bloqueo por pánico en un hilo. Se mitiga mediante la recuperación explícita del estado con `unwrap_or_else`.

#### Alternativa 2. `tokio::sync::Mutex`
**Positivas:**
* Permite sintaxis asíncrona dentro de la sección crítica.

**Negativas:**
* Induce a la serialización del servicio por retención prolongada del candado.

**Riesgos:**
* Cuellos de botella en la atención de clientes bajo cargas de trabajo concurrentes.

#### Alternativa 3. Modelo de Actores
**Positivas:**
* Exclusión mutua garantizada por diseño sin uso de primitivas de sincronización explícitas.

**Negativas:**
* Latencia adicional por el paso de mensajes inter-tareas y sobrecoste estructural en los manejadores de eventos.

**Riesgos:**
* Bloqueo completo del motor de ejecución ante una falla no capturada en la tarea principal.

---

### Mecanismos de Creación y Control de Procesos Hijos

#### Opción 1. `tokio::process` con PGID (Seleccionada)
**Positivas:**
* Monitoreo no bloqueante del ciclo de vida de los procesos e interrupción limpia de árboles de procesos completos mediante PGID.

**Negativas:**
* Requerimiento de refactorizar el ejecutor para aislar la propiedad de `Child` en una tarea dedicada.

**Riesgos:**
* Procesos que evadan la señal del grupo mediante la creación de nuevas sesiones (`setsid`). Se documenta como límite conocido del sistema.

#### Opción 2. `std::process` con Hilos
**Positivas:**
* Simplicidad en la invocación de procesos sin dependencias externas.

**Negativas:**
* Degradación del rendimiento por la creación indefinida de hilos del sistema operativo.

**Riesgos:**
* Agotamiento de recursos del sistema bajo ráfagas de solicitudes.

#### Opción 3. `fork`/`exec` con `pidfd`
**Positivas:**
* Inmunidad ante problemas de reutilización de PIDs en el kernel.

**Negativas:**
* Complejidad de mantenimiento y adición de bloques `unsafe`.

**Riesgos:**
* Errores de fuga de descriptores de archivo en la gestión manual del kernel.

## Requisitos afectados

### Estado Compartido (`std::sync::Mutex`)
* **+RF-03:** Garantiza la modificación atómica de la cola y la tabla de trabajos en memoria.
* **+RF-05 / +RNF-07:** La reserva de cupos de concurrencia se ejecuta de forma atómica previo al lanzamiento del proceso.
* **+RNF-27:** Preserva la consistencia de las transiciones de la FSM en la sección crítica.
* **-RNF-34:** Requiere pruebas de estrés para validar la ausencia de contención en el bloqueo.

### Gestión de Procesos (`tokio::process` + PGID)
* **+RF-04:** Aislamiento de los procesos respecto al flujo principal de atención del cliente.
* **+RF-10 / +RF-26:** Cancelación efectiva de trabajos en estado `QUEUED` y `RUNNING` mediante señalización al PGID.
* **+RNF-30:** Cierre controlado del servicio asegurando la finalización y recolección de los procesos activos.

## Prevención de Condiciones de Carrera y Procesos Zombi

### Condiciones de Carrera
1. **Atomicidad en FSM:** Toda modificación de estado sigue la máquina de estados de A2-01. La primera solicitud en modificar el estado dentro del bloqueo determina la acción; solicitudes concurrentes posteriores leen el estado actualizado y devuelven una respuesta no contradictoria.
2. **Reserva de Concurrencia:** La verificación y decremento de cupos disponibles se ejecuta en la misma sección crítica que transiciona el trabajo a `RUNNING`.
3. **Persistencia Desacoplada:** Las operaciones de escritura en la base de datos (SQLite) se ejecutan fuera de la sección crítica del `Mutex`.

### Control de Procesos Zombi
1. **Propiedad Única:** La tarea supervisora conserva la propiedad de la estructura `Child` durante todo el ciclo de vida del trabajo.
2. **Recolección Obligatoria:** La transición final a los estados `SUCCEEDED`, `FAILED` o `CANCELED` se emite únicamente posterior a la resolución del método `.wait()` del proceso hijo.
3. **Secuencia de Cancelación:** Para trabajos activos, la tarea supervisora envía la señal `SIGTERM` al PGID, espera la ventana de gracia configurable y aplica `SIGKILL` si el proceso persiste, ejecutando finalmente `wait()` antes de notificar el cambio de estado.

## Riesgos y Mitigaciones

| # | Riesgo | Mitigación | Prueba de Validación |
|---|---|---|---|
| 1 | Retención del `Mutex` durante operaciones de E/S | Aislamiento de llamadas asíncronas fuera del bloque de código del candado | TC-018 (20 envíos concurrentes) |
| 2 | Bloqueo envenenado por pánico en hilo | Manejo explícito con `unwrap_or_else(|e| e.into_inner())` | Pruebas de inyección de pánico |
| 3 | Divergencia entre estado en FSM y proceso en SO | Cambio a estado `CANCELED` supeditado a la recolección del proceso con `wait()` | TC-005 / TC-017 |
| 4 | Escape de procesos hijos vía `setsid()` | Documentación explícita de límites operativos del sistema | Guía Técnica (Sección 6) |
