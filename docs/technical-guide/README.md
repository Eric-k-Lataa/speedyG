## 1. Visión General

SpeedyG es un motor de ejecución de trabajos concurrentes para entornos Linux. La arquitectura del daemon sigue un modelo asíncrono basado en Tokio, coordinado con una máquina de estados finitos (Event Loop + FSM).

```text
                 Cliente (speedyg)
                        |
              +---------+---------+
              |                   |
         [Socket Unix]        [Socket TCP]
              |                   |
              +---------+---------+
                        |
                  Daemon (speedyG)
                        |
                 tokio::spawn
                 (por conexión)
                        |
                 Scheduler (Mutex)
                [Cola + FSM + Tabla]
                        |
                        v
                    Executor
                        |
                  Proceso hijo
                     (sh -c)
                        |
                  stdout / stderr
                        |
                   Persistencia
                  (SQLite / JSON)
```

### Componentes Principales

* **Cliente (`speedyg`):** Interfaz de línea de comandos responsable de estructurar las peticiones, comunicarse con el daemon mediante el socket Unix o TCP y mostrar las respuestas recibidas.

* **Daemon (`speedyG`):** Proceso servidor que gestiona las conexiones entrantes mediante Tokio, asignando una tarea asíncrona dedicada por cliente.

* **Programador (`Scheduler`):** Módulo central protegido por `Arc<Mutex<Scheduler>>` que administra la cola de espera, el historial de trabajos, los límites de concurrencia y las transiciones de la FSM.

* **Ejecutor / Supervisor (`Executor`):** Componente encargado de iniciar los procesos hijos mediante `sh -c`, supervisar su ejecución, capturar stdout y stderr, gestionar su grupo de procesos (PGID) y recolectar su estado de salida.

* **Persistencia:** Capa de almacenamiento basada en SQLite y mecanismos de respaldo JSON, utilizada para conservar y recuperar el estado de los trabajos ante reinicios del daemon.


## 2. Requisitos del sistema

La implementación de `speedyG` se rige por los requisitos funcionales y no funcionales definidos para el proyecto. Estos establecen las capacidades que debe proporcionar el servicio, así como las restricciones de rendimiento, confiabilidad, seguridad y operación.

### 2.1 Requisitos funcionales

Los requisitos funcionales (RF-01 a RF-30) especifican las operaciones y comportamientos que debe ofrecer el sistema. Se agrupan en las siguientes áreas:

- **Gestión de trabajos:** recepción, validación, identificación, encolamiento y ejecución de solicitudes.
- **Ciclo de vida y control:** administración de estados, consulta de trabajos, filtros y cancelación.
- **Salida, persistencia y recuperación:** captura de `stdout` y `stderr`, almacenamiento de resultados y recuperación tras reinicios.
- **Operación y configuración:** inicio, cierre controlado y parametrización del servicio.
- **Acceso remoto privado:** comunicación entre clientes y daemon mediante el protocolo definido.
- **Administración:** consulta de salud, aplicación de límites y manejo de solicitudes rechazadas.
- **Condiciones operativas:** concurrencia, duplicados, desconexiones, terminación de procesos y escalamiento de cancelaciones.

### 2.2 Requisitos no funcionales

Los requisitos no funcionales (RNF-01 a RNF-34) establecen las propiedades de calidad y las restricciones técnicas del sistema. Se organizan en las siguientes categorías:

- **Plataforma y portabilidad:** compatibilidad con Linux, construcción reproducible y operación sin privilegios de root.
- **Rendimiento y capacidad:** concurrencia, tiempos de respuesta y capacidad de almacenamiento.
- **Confiabilidad y robustez:** aislamiento de fallos, recuperación y consistencia de los datos.
- **Seguridad:** restricciones de acceso, validación de mensajes y aplicación del principio de mínimo privilegio.
- **Mantenibilidad y calidad:** modularidad, documentación, compilación y pruebas automatizadas.
- **Observabilidad y usabilidad:** diagnóstico de errores, trazabilidad y facilidad de operación.
- **Calidad de red:** manejo de mensajes fragmentados, liberación de recursos y restricciones de acceso remoto.
- **Consistencia y recuperación:** transiciones de estado, control de presión de carga, recuperación y pruebas de estrés.

### 2.3 Verificación y trazabilidad

Cada requisito debe estar asociado con uno o más casos de verificación. Su cumplimiento se determina mediante la implementación correspondiente, el resultado esperado y la evidencia registrada en la matriz de trazabilidad.

## 3. Arquitectura del sistema

El sistema sigue una arquitectura cliente-servidor. El cliente CLI (`speedyg`) envía solicitudes al daemon (`speedyG`) mediante un socket de dominio Unix o una conexión TCP. El daemon procesa las solicitudes de forma asíncrona y delega la administración de los trabajos al planificador.

### 3.1 Componentes principales

- **Cliente CLI:** construye y envía solicitudes al servicio, y presenta las respuestas al usuario.
- **Daemon:** administra las conexiones entrantes, valida las solicitudes y coordina el funcionamiento del servicio.
- **Planificador (Scheduler):** mantiene la cola de trabajos, administra sus estados y controla su despacho según los límites de concurrencia.
- **Ejecutor (Executor):** crea y supervisa los procesos hijos, captura sus salidas y gestiona su terminación.
- **Capa de persistencia:** almacena y recupera los metadatos y resultados de los trabajos mediante SQLite y JSON.

### 3.2 Modelo de concurrencia

El daemon utiliza Tokio para gestionar las conexiones y las tareas asíncronas. El estado compartido del planificador se protege mediante un `Arc<Mutex<Scheduler>>`, lo que permite coordinar las solicitudes concurrentes y mantener la consistencia de la cola y del historial.

Cada trabajo despachado se ejecuta en un proceso hijo independiente. El número de procesos activos está limitado por el parámetro `max_current`, mientras que `queue_cap` establece la capacidad máxima de trabajos pendientes.

### 3.3 Comunicación entre componentes

La comunicación entre el cliente y el daemon utiliza un protocolo con encabezado de versión. Las solicitudes recibidas se validan y se procesan según la operación solicitada. Las operaciones de ejecución se incorporan al planificador, mientras que las consultas y solicitudes de control acceden al estado correspondiente del servicio.

### 3.4 Binarios y componentes ejecutables

El proyecto proporciona dos binarios ejecutables:

- **`speedyG`:** implementa el proceso servidor (daemon). Se encarga de inicializar el servicio, gestionar las conexiones, coordinar el planificador, supervisar la ejecución de trabajos y administrar la persistencia.
- **`speedyg`:** implementa el cliente de línea de comandos (CLI). Permite enviar solicitudes al daemon, consultar el estado de los trabajos y ejecutar operaciones de control.

Ambos binarios se generan mediante el sistema de construcción de Cargo a partir del proyecto Rust. Su ejecución es independiente: el daemon debe encontrarse activo para que el cliente pueda enviar solicitudes y recibir respuestas.

## 4. Procesos y Señales

La gestión de procesos en SpeedyG se rige por las especificaciones del ADR-05:

* **Invocación:** Los comandos se ejecutan invocando la variante `sh -c "<comando>"`, habilitando el uso de encadenamientos, tuberías y operaciones nativas del Shell.

* **Aislamiento por Grupo:** Cada trabajo se ejecuta bajo su propio grupo de procesos (PGID), lo que permite enviar señales de terminación a los procesos pertenecientes a dicho grupo.

* **Supervisión y Recolección:** Cada proceso cuenta con una tarea supervisora dedicada que conserva el control del proceso hijo, monitorea su ejecución y realiza la llamada asíncrona wait() para recolectar su estado y evitar procesos zombi.


### Control de Señales

| Señal | Origen | Propósito |
| --- | --- | --- |
| `SIGTERM` | Daemon | Intento inicial de cancelación limpia enviado al PGID del trabajo. |
| `SIGKILL` | Daemon | Escalamiento forzado enviado al PGID tras agotar la ventana de gracia. |
| `SIGTERM` / `SIGINT` | Sistema / Operador | Solicitud de apagado controlado del daemon;  detiene la recepción de nuevas conexiones y gestiona los procesos en curso.

### Protocolo de Cancelación

1. **Estado `QUEUED`:** El trabajo es removido de la cola de espera y pasa a CANCELED. No se realiza ningún lanzamiento de proceso.

2. **Estado `RUNNING`:**  El trabajo pasa a CANCELED y se envía SIGTERM al PGID del proceso. Se espera el tiempo configurado mediante grace_ms. Si el grupo de procesos continúa existiendo al finalizar el plazo, se envía SIGKILL. La tarea supervisora continúa con la recolección del proceso mediante wait().

3. **Estados Terminales:** Si el trabajo ya se encuentra en un estado final o no existe, el sistema retorna una respuesta informativa sin alterar el estado en la FSM.


## 5. Máquina de Estados (FSM)

El ciclo de vida de los trabajos sigue las reglas de transición definidas en el modelo A2-01:

```text
[Inicio] ──> QUEUED ──> RUNNING ──┬──> SUCCEEDED
               │           │      ├──> FAILED
               v           │      └──> CANCELED
           CANCELED        └──> INTERRUPTED

```

* **Estados Terminales:** `SUCCEEDED`, `FAILED`, `CANCELED` e `INTERRUPTED`. Son inmutables; no se permiten regresiones de estado.


* **Recuperación tras Reinicio:** El comportamiento depende de cómo se interrumpa el daemon:
  - **Apagado mediante Ctrl+C:** Los trabajos que estaban en `RUNNING` se cancelan. Al liberarse espacios de ejecución, los trabajos que estaban en `QUEUED` pasan a `RUNNING`. Cuando el daemon termina y se inicia nuevamente, los trabajos que quedaron en `RUNNING` pasan a `INTERRUPTED`.
  - **Terminación abrupta (por ejemplo, al cerrar la terminal):** Los trabajos que estaban en `RUNNING` al momento de la interrupción pasan a `INTERRUPTED`, mientras que los que permanecían en `QUEUED` conservan ese estado y pueden volver a despacharse.

## 6. Configuración del Sistema

El comportamiento del daemon se ajusta mediante parámetros de configuración en el arranque:

| Parámetro | Descripción | Requisito | Valor Predeterminado |
| --- | --- | --- | --- |
| `socket_path` | Ruta del socket de dominio Unix | RF-16 | `/tmp/speedyg.sock` |
| `data_dir` | Directorio de datos configurado para el servicio | RF-12, RF-16 | `/tmp/speedyg-data` |
| `max_current` | Límite máximo de trabajos en ejecución simultánea | RF-05, RNF-07 | `3` |
| `queue_cap` | Capacidad máxima de la cola de espera, adicional a los trabajos en ejecución | RF-23, RF-25 | `3` |
| `grace_ms` | Tiempo de espera entre `SIGTERM` y `SIGKILL`, expresado en milisegundos | RF-30 | `5000` |
| `max_message_bytes` | Tamaño máximo permitido para un mensaje recibido | RNF-18 | `65536` |
| `max_arguments` | Número máximo de argumentos permitidos por trabajo | RNF-18 | `32` |
| `max_argument_bytes` | Longitud máxima permitida por argumento, en bytes | RNF-18 | `256` |
| `max_output_bytes` | Cantidad máxima de salida almacenada por trabajo, en bytes | ADR-07 | `1000000` |
| `max_completed_jobs` | Cantidad máxima de trabajos terminados conservados en el historial | ADR-07 | `1000` |
| `tcp_enabled` | Habilita o deshabilita las conexiones TCP | RF-16, RNF-12 | `true` |
| `tcp_host` | Dirección IP en la que escucha el servicio TCP | RF-16, RNF-12 | `127.0.0.1` |
| `tcp_port` | Puerto TCP utilizado por el servicio | RF-16, RNF-12 | `7878` |

La configuración puede establecerse mediante argumentos de línea de comandos o variables de entorno con el prefijo `SPEEDYG_`. Se aplica el siguiente orden de precedencia: argumentos CLI, variables de entorno y valores predeterminados.

Para habilitar conexiones TCP desde otras interfaces distintas de loopback, es obligatorio configurar `tcp_allowlist` con las direcciones IP autorizadas. Si no se proporciona una lista de direcciones permitidas, el daemon rechaza la configuración.

## 7. Persistencia y Registros

- **Almacenamiento:** SpeedyG utiliza SQLite como mecanismo principal de persistencia y un archivo JSON como respaldo. La base de datos contiene las tablas `jobs` y `meta`. La primera almacena los trabajos y sus atributos; la segunda conserva el siguiente identificador disponible.

- **Estructura de los datos:** Cada trabajo almacena su identificador, programa, argumentos, estado, código de salida, salida estándar, salida de error, indicador de truncamiento y marcas de tiempo (`received_at`, `started_at` y `finished_at`). También se registra su ubicación (`queue` o `history`) y posición para conservar el orden. Los argumentos se serializan como arreglos JSON y las marcas de tiempo utilizan el formato RFC 3339, compatible con ISO 8601. El respaldo JSON serializa la estructura completa del planificador.

- **Integridad:** Las operaciones de escritura en SQLite utilizan transacciones. El respaldo JSON se escribe en un archivo temporal antes de sustituir el archivo anterior. Si falla el respaldo JSON, el servicio registra una advertencia, siempre que el guardado en SQLite haya sido exitoso.

- **Configuración de rutas:** Las ubicaciones de los archivos se configuran mediante las variables de entorno `SPEEDYG_DB` y `SPEEDYG_JSON`. Si no se especifican, se utilizan `speedyg.db` y `scheduler.json`, respectivamente.

- **Recuperación:** Durante el inicio del daemon, la recuperación sigue el orden SQLite → JSON → Scheduler vacío. Si no es posible recuperar la información de ninguno de los dos formatos, se inicializa un planificador vacío.

- **Trazabilidad:** El daemon utiliza `tracing` para registrar eventos, advertencias y errores durante su ejecución.

## 8. Límites Conocidos

1. **Desvinculación de Sesión:** Si un comando ejecutado invoca explícitamente `setsid()`, sus procesos descendientes pueden crear una nueva sesión y escapar a las señales enviadas al PGID original del trabajo.

2. **Bloqueos en Kernel:** Los procesos en estado de espera no interrumpible (estado `D` en `ps`) pueden no responder inmediatamente a `SIGKILL` hasta que finalice la operación de E/S del kernel.

3. **Capacidad de Cola:** Al alcanzar la capacidad máxima establecida en `queue_cap`, las nuevas peticiones de envío son rechazadas con un error de saturación. Esta capacidad corresponde únicamente a los trabajos en espera, independientemente de los que están en ejecución.

4. **Terminación del Daemon:** La forma en que finaliza el daemon afecta la recuperación de los trabajos y sus estados. El apagado mediante `Ctrl+C` y la terminación abrupta pueden producir resultados diferentes, como se describe en el apartado 5.

## 9. Seguridad y Amenazas

SpeedyG contempla las siguientes amenazas y medidas de mitigación:

| Amenaza | Riesgo | Medida de mitigación |
|---|---|---|
| Acceso no autorizado al servicio | Envío de trabajos o ejecución de comandos sin autorización. | Restringir el acceso a la red privada o VPN y utilizar `tcp_allowlist` para conexiones TCP que no sean locales. |
| Saturación de recursos | Acumulación excesiva de trabajos pendientes o ejecución concurrente de demasiados procesos. | Límites independientes mediante `queue_cap` y `max_current`, además de límites de salida y retención del historial. |
| Cancelación incorrecta de procesos | Terminación de procesos ajenos al trabajo solicitado. | Cada trabajo utiliza su propio grupo de procesos para gestionar su cancelación. |
| Terminación inesperada del daemon | Pérdida del estado operativo de los trabajos durante un cierre abrupto. | Persistencia en SQLite y respaldo JSON para recuperar el estado del planificador. |
| Procesos descendientes fuera del grupo original | Algunos procesos pueden escapar del grupo de procesos mediante mecanismos como `setsid()`. | Limitación conocida: no se garantiza la terminación de todos los procesos descendientes. |

El servicio no debe exponerse directamente a redes públicas. El uso de una VPN o red privada restringe el alcance de las conexiones, pero no sustituye un mecanismo de autenticación de clientes.

## 10. Ejecución de Pruebas de Verificación

Previo a la integración de cambios, se recomienda ejecutar las comprobaciones estándar del proyecto:

```bash
# Formato y análisis estático
cargo fmt --check
cargo clippy -- -D warnings

# Pruebas unitarias e integración
cargo test

# Ejecución de todos los casos de verificación
./verif/scripts/run-all.sh
```

### Casos de Verificación

Los scripts disponibles en `verif/scripts/` corresponden a los siguientes casos:

- TC-001 a TC-009
- TC-014
- TC-016 a TC-018
- TC-020 a TC-022
- TC-024

Los resultados de ejecución se almacenan en la ruta `verif/results/<TC_ID>/<TIMESTAMP>/`, generando los archivos `summary.txt`, `output.log` y `environment.txt`.

Para inspeccionar la existencia de procesos huérfanos o zombi durante la ejecución de las pruebas:

```bash
ps -eo pid,ppid,pgid,stat,args | grep -E 'speedyG|sleep'
```

## 11. Interfaces y Manejo de Errores

El cliente CLI retorna un código de estado `0` ante ejecuciones exitosas y un valor diferente de `0` ante fallos.

Los mensajes de error generados por el servicio proporcionan información sobre la **operación fallida**, la **causa del error** y la **acción correctiva sugerida**, facilitando la identificación y resolución de problemas.

El servicio acepta conexiones mediante un socket de dominio Unix y, opcionalmente, mediante TCP. Las peticiones utilizan un encabezado de versión con el formato `v=<major>.<minor>|<comando>`. La única versión admitida del protocolo es `1.0`; cualquier versión diferente es rechazada explícitamente.

Las operaciones soportadas por el protocolo son:

- `help`: solicita la descripción de los comandos y operaciones disponibles en el servicio.
- `status`: obtiene el estado de los trabajos registrados, incluyendo los trabajos en ejecución, pendientes y el historial de trabajos finalizados.
- `status <id>`: consulta los metadatos y el estado de un trabajo identificado por su ID.
- `list`: alias de `status`, permite consultar el listado de trabajos registrados.
- `health`: obtiene información sobre el estado operativo del daemon y sus métricas de ejecución.
- `cancel <id>`: solicita la cancelación del trabajo identificado por su ID. Si el trabajo está en ejecución, se inicia el procedimiento de terminación del proceso asociado.
- **Envío de comandos externos:** registra una nueva solicitud de ejecución. El servicio valida los argumentos, asigna un identificador único al trabajo y lo incorpora a la cola de planificación para su posterior despacho, sujeto a los límites de concurrencia y capacidad configurados.