# SpeedyG — Guía Técnica

## 1. Visión General
SpeedyG es un motor de ejecución de trabajos concurrentes para entornos Linux[cite: 32, 42]. La arquitectura del daemon sigue un modelo de bucle de eventos reactivo coordinado con máquinas de estado finitas (Event Loop + FSM).

```text
Cliente (speedyg) ──[Socket Unix]──> Daemon (speedyG)
                                          │
                                   tokio::spawn (por conexión)
                                          │
                                    v─────┴────────┐
                             Scheduler (Mutex)     │
                             [Cola + FSM + Tabla]  │
                                    │              │
                                    v              v
                              Supervisor ──> Executor (tokio::process)
                                                   │
                                                   ├── PGID (sh -c)
                                                   └── Persistencia (SQLite)
```

### Componentes Principales

* **Cliente (`speedyg`):** Interfaz de línea de comandos responsable de estructurar las peticiones, comunicarse con el daemon mediante el socket Unix y retornar códigos de salida estándar.

* **Daemon (`speedyG`):** Proceso servidor que gestiona las conexiones entrantes asignando una tarea asíncrona dedicada por cliente.

* **Programador (`Scheduler`):** Módulo central protegido por exclusión mutua (`std::sync::Mutex`) que administra la cola de espera, la tabla de trabajos, los límites de concurrencia y las reglas de transición de la FSM.

* **Ejecutor / Supervisor (`Executor`):** Tarea asíncrona encargada de instanciar el proceso hijo mediante un Shell (`sh -c`), monitorear su ejecución, exponer su PGID, aplicar señales de interrupción y recolectar su estado de salida.

* **Persistencia:** Capa de almacenamiento SQLite para preservar el estado de las tareas ante reinicios del daemon.


## 2. Procesos y Señales

La gestión de procesos en SpeedyG se rige por las especificaciones del ADR-05:

* **Invocación:** Los comandos se ejecutan invocando la variante `sh -c "<comando>"`, habilitando el uso de encadenamientos, tuberías y operaciones nativas del Shell.

* **Aislamiento por Grupo:** Cada trabajo se ejecuta bajo su propio grupo de procesos (PGID), permitiendo el control sobre el árbol completo de procesos descendientes.

* **Supervisión y Recolección:** Cada proceso cuenta con una tarea supervisora dedicada que actúa como única propietaria de la estructura de control del proceso, garantizando la invocación de la llamada `wait()` para prevenir procesos zombi.


### Control de Señales

| Señal | Origen | Propósito |
| --- | --- | --- |
| `SIGTERM` | Daemon | Intento inicial de cancelación limpia enviado al PGID del trabajo. |
| `SIGKILL` | Daemon | Escalamiento forzado enviado al PGID tras agotar la ventana de gracia. |
| `SIGTERM` / `SIGINT` | Sistema / Operador | Solicitud de apagado controlado del daemon; detiene la recepción de trabajos y recolecta los procesos en curso.|

### Protocolo de Cancelación

1. **Estado `QUEUED`:** El trabajo es removido de la cola de espera. No se realiza ningún lanzamiento de proceso.

2. **Estado `RUNNING`:** Se emite `SIGTERM` al PGID del trabajo. Se inicia un temporizador basado en el parámetro `kill_grace_secs`. Si el proceso persiste al finalizar el plazo, se emite `SIGKILL`. La FSM transiciona a `CANCELED` únicamente tras completar la recolección del proceso vía `wait()`.

3. **Estados Terminales:** Si el trabajo ya se encuentra en un estado final o no existe, el sistema retorna una respuesta informativa sin alterar el estado en la FSM.


## 3. Máquina de Estados (FSM)

El ciclo de vida de los trabajos sigue las reglas de transición definidas en el modelo A2-01:

```text
[Inicio] ──> QUEUED ──> RUNNING ──┬──> SUCCEEDED
               │           │      ├──> FAILED
               v           │      └──> CANCELED
           CANCELED        └──> INTERRUPTED

```

* **Estados Terminales:** `SUCCEEDED`, `FAILED`, `CANCELED` e `INTERRUPTED`. Son inmutables; no se permiten regresiones de estado.


* **Recuperación tras Reinicio:** Los trabajos que figuren en estado `QUEUED` o `RUNNING` en la capa de persistencia al momento de iniciar el daemon se evalúan y transicionan al estado `INTERRUPTED` para mantener la coherencia del sistema.


## 4. Configuración del Sistema

El comportamiento del daemon se ajusta mediante parámetros de configuración en el arranque:

| Parámetro | Descripción | Requisito | Valor Predeterminado |
| --- | --- | --- | --- |
| `socket_path` | Ruta del socket de dominio Unix | RF-16 | `/tmp/speedyg.sock` |
| `data_dir` | Directorio de almacenamiento para la base de datos y logs | RF-12, RF-16 | `/var/lib/speedyg` |
| `max_concurrent` | Límite máximo de trabajos en ejecución simultánea | RF-05, RNF-07 | `4` |
| `max_queue` | Capacidad máxima de la cola de espera | RF-23, RF-25 | `100` |
| `kill_grace_secs` | Ventana de tiempo entre `SIGTERM` y `SIGKILL` | RF-30 | `5` |
| `retention_days` | Periodo de retención de registros de ejecución | ADR-04 | `7`|
| `listen_addr` | Dirección IP de escucha para conexiones | RF-16, RNF-12 | `127.0.0.1`|
| `port` | Puerto TCP para servicio en red | RF-16, RNF-12 | `8080`|

## 5. Persistencia y Registros

* **Base de Datos:** Los metadatos de las tareas y sus estados se almacenan mediante SQLite. La reconstrucción de la FSM se ejecuta durante la fase de inicialización del `Scheduler`.

* **Aislamiento de E/S:** Las operaciones de lectura y escritura en la base de datos se ejecutan de manera asíncrona fuera de las secciones críticas del `Mutex` de estado.

* **Trazabilidad:** Cada entrada en la bitácora incluye marca de tiempo en formato ISO 8601 y el identificador único del trabajo asociado.


## 6. Límites Conocidos

1. **Desvinculación de Sesión:** Si un comando ejecutado invoca explícitamente `setsid()`, sus procesos descendientes crean una nueva sesión y escapan a las señales enviadas al PGID.

2. **Bloqueos en Kernel:** Procesos en estado de espera no interrumpible (estado `D` en `ps`) no responderán de forma inmediata a la señal `SIGKILL` hasta finalizar la operación de E/S del kernel.

3. **Capacidad de Cola:** Al alcanzar la capacidad máxima establecida en `max_queue`, las nuevas peticiones de envío son rechazadas con un error de saturación.


## 7. Ejecución de Pruebas de Verificación

Previo a la integración de cambios, se debe ejecutar la suite de comprobación estándar:

```bash
# Formato y análisis estático
cargo fmt --check
cargo clippy -- -D warnings

# Pruebas unitarias e integración
cargo test

# Scripts de verificación automatizada
./verif/scripts/TC-001.sh
./verif/scripts/TC-017.sh
./verif/scripts/TC-018.sh

```

Los resultados de ejecución se almacenan en la ruta `verif/results/<TC_ID>/<TIMESTAMP>/`, generando los archivos `summary.txt`, `output.log` y `environment.txt`.

Para inspeccionar la existencia de procesos huérfanos o zombi durante la ejecución de las pruebas:

```bash
ps -eo pid,ppid,pgid,stat,args | grep -E 'speedyG|sleep'

```

## 8. Interfaces y Manejo de Errores

El cliente CLI retorna un código de estado `0` ante ejecuciones exitosas y un valor diferente de `0` ante fallos. Los mensajes de error generados por el servicio estructuran su información indicando la **operación fallida**, la **causa raíz** y la **acción correctiva sugerida**.

