# Protocolo de comunicación de speedyG

## 1. Introducción

Este documento describe el protocolo de comunicación utilizado por speedyG para intercambiar comandos y respuestas entre los clientes y el demonio

El protocolo utiliza mensajes JSON codificados en UTF-8 y delimitados por saltos de línea (NDJSON). Los clientes envían solicitudes al demonio y reciben respuestas con el resultado de las operaciones solicitadas.

## 2. Transporte y conexión

speedyG permite la comunicación mediante los siguientes mecanismos:

### 2.1. Unix Domain Socket

La comunicación local se realiza mediante un Unix Domain Socket

- **Ruta predeterminada:** `/tmp/speedyg.sock`
- **Configuración:** puede modificarse mediante el argumento `--socket` o la variable de entorno `SPEEDYG_SOCKET`
- **Precedencia:** argumento de línea de comandos, variable de entorno y, finalmente, valor predeterminado

El cliente establece una conexión con el socket antes de enviar el comando

### 2.2. TCP (Transmission Control Protocol)

El demonio también puede habilitar la comunicación mediante TCP

- **Dirección predeterminada:** `127.0.0.1`
- **Puerto predeterminado:** `7878`
- **Estado predeterminado:** habilitado
- **Configuración:** puede modificarse mediante los argumentos `--tcp-enabled`, `--tcp-host` y `--tcp-port`, o mediante sus variables de entorno correspondientes

Cuando se configura una dirección que no es de loopback, es necesario definir una lista de direcciones IP autorizadas (`tcp_allowlist`).

El demonio verifica la dirección IP del cliente. Si no está autorizada, rechaza la conexión

Para el acceso remoto, se contempla el uso de un túnel SSH. No se recomienda exponer directamente el servicio TCP a redes no confiables.

## 3. Formato de los mensajes

### 3.1. Codificación

Los mensajes se transmiten como objetos JSON codificados en UTF-8.

Cada mensaje, tanto las solicitudes del cliente como las respuestas del demonio, debe incluir la versión del protocolo mediante el campo `protocol_version`, cuyo valor utiliza el formato SemVer. La versión inicial es `0.0.1`.

El receptor valida que los bytes recibidos representen texto UTF-8 válido y que el contenido sea un objeto JSON válido. Si alguna validación falla, rechaza el mensaje y devuelve el error correspondiente.

### 3.2. Delimitación de mensajes (framing)

El protocolo utiliza JSON delimitado por línea (NDJSON). El carácter de salto de línea (`\n`) marca el final de cada mensaje.

- Cada mensaje debe finalizar con `\n`.
- También se acepta el formato CRLF (`\r\n`).
- Si el cliente cierra su flujo de escritura sin enviar un salto de línea, el demonio procesa los datos recibidos hasta ese momento como el último mensaje, siempre que formen un mensaje JSON válido.
- Una conexión puede contener varios mensajes, siempre que estén separados por saltos de línea.

El delimitador no forma parte del contenido JSON del mensaje.

### 3.3. Envío y recepción

El intercambio de mensajes sigue este flujo:

1. El cliente establece una conexión con el demonio mediante Unix Domain Socket o TCP
2. El cliente construye un objeto JSON con la información necesaria para la solicitud, incluida la versión del protocolo y, cuando corresponda, la operación solicitada
3. El cliente codifica el objeto JSON en UTF-8 y lo envía terminado en `\n`
4. El demonio recibe el mensaje, lo valida y procesa la operación solicitada
5. El demonio devuelve una respuesta como objeto JSON, también codificada en UTF-8 y delimitada por `\n`

El envío y la recepción deben contemplar lecturas y escrituras parciales, acumulando los datos recibidos hasta completar un mensaje y utilizando escritura completa para transmitir las respuestas.

### 3.4. Validación de mensajes

El demonio realiza las siguientes validaciones antes de procesar una operación:

- El mensaje no debe estar vacío.
- Los bytes recibidos deben representar texto UTF-8 válido.
- El contenido debe ser un objeto JSON válido.
- Debe incluir una versión del protocolo válida y compatible con la admitida por el demonio.
- No debe superar el tamaño máximo permitido.
- Debe incluir los campos requeridos por la operación solicitada.
- Los valores de los campos deben cumplir las restricciones establecidas para cada operación.

Si un mensaje no cumple alguna de estas condiciones, el demonio lo rechaza y devuelve el error correspondiente.

### 3.5. Estructura de los mensajes

Las solicitudes y respuestas intercambiadas entre el cliente y el demonio utilizan objetos JSON.

**Solicitudes**

La operación de envío de trabajos (submit) constituye una excepción: se identifica mediante los campos `program` y `args` dentro de `data`, por lo que no requiere el campo operation. Las demás operaciones incluyen este campo para indicar la acción solicitada.

Cada solicitud incluye los siguientes campos:

| Campo | Tipo | Descripción |
|---|---|---|
| `protocol_version` | String | Versión del protocolo utilizada por el cliente |
| `operation` | String | Operación solicitada al demonio (no se incluye en las solicitudes de envío de trabajos |
| `data` | Object | Datos necesarios para realizar la operación |

Ejemplo de solicitud para enviar un trabajo:

```json
{
  "protocol_version": "0.0.1",
  "data": {
    "program": "echo",
    "args": ["Hola", "mundo"]
  }
}
```

**Respuestas**

Cada respuesta incluye los siguientes campos:

| Campo | Tipo | Descripción |
|---|---|---|
| `protocol_version` | String | Versión del protocolo utilizada por el demonio |
| `status` | String | Resultado de la solicitud: `ok` o `error` |
| `data` | Object o null | Información devuelta por la operación |
| `error` | Object o null | Información del error, cuando corresponda |

Ejemplo de respuesta exitosa:

```json
{
  "protocol_version": "0.0.1",
  "status": "ok",
  "data": {
    "job_id": 1,
    "message": "Job #1 encolado correctamente"
  },
  "error": null
}
```

Ejemplo de respuesta con error:

```json
{
  "protocol_version": "0.0.1",
  "status": "error",
  "data": null,
  "error": {
    "message": "La cola está llena (capacidad: 3). Espera a que se libere un espacio"
  }
}
```

## 4. Formato y procesamiento de comandos

### 4.1. Estructura de los comandos

Las peticiones se realizan mediante el cliente de línea de comandos `speedyg`, que establece la conexión con el demonio y envía la operación solicitada.

La estructura general es:

```text
speedyg <comando> [argumentos]
```

- `speedyg`: cliente encargado de establecer la conexión con el demonio.
- `<comando>`: operación interna o nombre de un programa externo.
- `[argumentos]`: parámetros adicionales del comando.

Ejemplos:

```bash
speedyg sleep 10
speedyg help
speedyg status
speedyg cancel 1
```

El cliente interpreta el comando y sus argumentos, construye la solicitud JSON correspondiente y la envía al demonio.

### 4.2. Separación de argumentos

El cliente utiliza espacios en blanco para separar el comando de sus argumentos.

- Se permiten uno o varios espacios entre elementos.
- Los espacios al inicio y al final no forman parte del comando.
- Las comillas no permiten agrupar varias palabras en un único argumento.

Por ejemplo:

```bash
speedyg echo Hola mundo
```

Se interpreta como:

- Programa: `echo`
- Argumentos: `Hola`, `mundo`

El cliente envía estos datos al demonio mediante los campos `program` y `args` de la solicitud JSON.

### 4.3. Comandos reservados

El demonio identifica los siguientes comandos como operaciones internas:

- `status`
- `list`
- `health`
- `cancel`
- `help`

Estos comandos tienen validaciones específicas y no se envían al ejecutor como programas externos

El comando `list` funciona como alias de `status` y no acepta argumentos

### 4.4. Ejecución de programas externos

Los comandos que no corresponden a operaciones reservadas se interpretan como programas externos y se envían al ejecutor.

Por ejemplo:

```bash
speedyg echo Hola
```

El cliente construye una solicitud `submit` con el programa `echo` y el argumento `Hola`. El demonio crea el trabajo y lo envía al scheduler

### 4.5. Restricciones de argumentos

El demonio aplica límites configurables durante el procesamiento de los comandos:

- Número máximo de argumentos: 32 por defecto
- Tamaño máximo por argumento: 256 bytes por defecto

El nombre del programa no se cuenta como argumento para el límite de cantidad de argumentos

Si se supera alguno de estos límites, el comando es rechazado y el demonio devuelve el error correspondiente

## 5. Operaciones

### 5.1. Envío de trabajos (submit)

La operación `submit` permite enviar un programa externo al demonio para crear un nuevo trabajo y agregarlo a la cola del scheduler.

**Sintaxis en la CLI:**

```bash
speedyg sleep 10
```

**Petición enviada al demonio:**

```json
{
  "protocol_version": "0.0.1",
  "data": {
    "program": "sleep",
    "args": ["10"]
  }
}
```

**Respuesta del demonio:**

```json
{
  "protocol_version": "0.0.1",
  "status": "ok",
  "data": {
    "job_id": 1,
    "message": "Job #1 encolado correctamente"
  },
  "error": null
}
```

**Salida mostrada al usuario:**

```text
Job #1 encolado correctamente
```

El identificador asignado permite consultar posteriormente el estado del trabajo o solicitar su cancelación.

Si la cola está llena, el demonio rechaza el nuevo trabajo y no le asigna un identificador.

**Respuesta de error del demonio:**

```json
{
  "protocol_version": "0.0.1",
  "status": "error",
  "data": null,
  "error": {
    "message": "La cola está llena (capacidad: 3). Espera a que se libere un espacio"
  }
}
```

**Salida mostrada al usuario:**

```text
Error al enviar 'sleep': la cola está llena (capacidad: 3). Espera a que se libere un espacio
```

### 5.2. Consulta de trabajos (status)

La operación `status` permite consultar los trabajos registrados en el demonio.

Tiene tres modalidades:

**a) Consultar todos los trabajos**

Muestra los trabajos pendientes, en ejecución y el historial de trabajos terminados.

**Sintaxis en la CLI:**

```bash
speedyg status
```

**Petición enviada al demonio:**

```json
{
  "protocol_version": "0.0.1",
  "operation": "status",
  "data": {}
}
```

**Respuesta del demonio:**

```json
{
  "protocol_version": "0.0.1",
  "status": "ok",
  "data": {
    "jobs": []
  },
  "error": null
}
```

**Salida mostrada al usuario cuando no existen trabajos:**

```text
No hay jobs registrados.
```

Cuando existen trabajos, el cliente muestra la información organizada en las secciones:

```text
--- Pendientes / En ejecución ---
--- Historial ---
```

Cada trabajo incluye su identificador, programa, argumentos y estado. También puede incluir el código de salida y los datos de ejecución disponibles.

**b) Consultar un trabajo por identificador**

Permite obtener información de un trabajo específico.

**Sintaxis en la CLI:**

```bash
speedyg status <id>
```

**Ejemplo:**

```bash
speedyg status 1
```

**Petición enviada al demonio:**

```json
{
  "protocol_version": "0.0.1",
  "operation": "status",
  "data": {
    "job_id": 1
  }
}
```

**Respuesta del demonio:**

```json
{
  "protocol_version": "0.0.1",
  "status": "ok",
  "data": {
    "job": {
      "job_id": 1,
      "program": "echo",
      "args": ["hola"],
      "state": "succeeded",
      "exit_code": 0,
      "received_at": "2026-11-26T19:01:57Z",
      "started_at": "2026-11-26T19:01:57Z",
      "finished_at": "2026-11-26T19:01:57Z",
      "stdout": "hola"
    }
  },
  "error": null
}
```

**Salida mostrada al usuario:**

```text
Job #1: echo hola [Succeeded] (exit code: 0)
  ├─ Recibido:  2026-11-26 19:01:57 UTC
  ├─ Iniciado:  2026-11-26 19:01:57 UTC
  └─ Finalizado: 2026-11-26 19:01:57 UTC
  [stdout]:
    │ hola
```

Si el trabajo no existe, el demonio devuelve un error

**Respuesta de error del demonio:**

```json
{
  "protocol_version": "0.0.1",
  "status": "error",
  "data": null,
  "error": {
    "message": "Job #1 no encontrado"
  }
}
```

**Salida mostrada al usuario:**

```text
Error: Job #1 no encontrado
```

**c) Filtrar trabajos por estado**

Permite consultar los trabajos que se encuentran en un estado determinado.

Los estados son:

- `queued`
- `running`
- `succeeded`
- `failed`
- `canceled`
- `interrupted`

**Sintaxis en la CLI:**

```bash
speedyg status <estado>
```

**Ejemplo:**

```bash
speedyg status running
```

**Petición enviada al demonio:**

```json
{
  "protocol_version": "0.0.1",
  "operation": "status",
  "data": {
    "state": "running"
  }
}
```

**Respuesta del demonio:**

```json
{
  "protocol_version": "0.0.1",
  "status": "ok",
  "data": {
    "jobs": [
      {
        "job_id": 35,
        "program": "sleep",
        "args": ["10"],
        "state": "running"
      },
      {
        "job_id": 36,
        "program": "sleep",
        "args": ["10"],
        "state": "running"
      }
    ]
  },
  "error": null
}
```

**Salida mostrada al usuario:**

```text
--- Jobs con estado 'running' ---
Job #35: sleep 10 [Running]
Job #36: sleep 10 [Running]
```

Si no existen trabajos con el estado solicitado, el cliente muestra:

```text
No hay jobs con el estado 'running'.
```

### 5.3. Listado de trabajos (list)

El comando `list` funciona como un alias de `status` y permite consultar todos los trabajos registrados en el demonio.

**Sintaxis en la CLI:**

```bash
speedyg list
```

El cliente transforma esta solicitud en la misma operación `status` utilizada para consultar todos los trabajos.

**Petición enviada al demonio:**

```json
{
  "protocol_version": "0.0.1",
  "operation": "status",
  "data": {}
}
```

La respuesta del demonio tiene la misma estructura que la consulta general de `status`.

**Salida mostrada al usuario:**

La salida tiene el mismo formato que `speedyg status`, mostrando los trabajos pendientes, en ejecución y el historial.

Si no existen trabajos registrados, muestra:

```text
No hay jobs registrados.
```

El comando `list` no acepta argumentos adicionales. Si se proporcionan, el cliente muestra un error de sintaxis.

### 5.4. Cancelación de trabajos (cancel)

La operación `cancel` permite solicitar la cancelación de un trabajo registrado en el demonio.

**Sintaxis en la CLI:**

```bash
speedyg cancel <id>
```

El identificador debe ser un número entero sin signo (`u32`).

**Ejemplo:**

```bash
speedyg cancel 1
```

**Petición enviada al demonio:**

```json
{
  "protocol_version": "0.0.1",
  "operation": "cancel",
  "data": {
    "job_id": 1
  }
}
```

**Resultados posibles:**

**a) Cancelación exitosa**

**Respuesta del demonio:**

```json
{
  "protocol_version": "0.0.1",
  "status": "ok",
  "data": {
    "job_id": 1,
    "message": "Job #1 cancelado correctamente"
  },
  "error": null
}
```

**Salida mostrada al usuario:**

```text
Job #1 cancelado correctamente
```

**b) El trabajo ya estaba cancelado**

**Respuesta del demonio:**

```json
{
  "protocol_version": "0.0.1",
  "status": "ok",
  "data": {
    "job_id": 1,
    "message": "Job #1 ya estaba cancelado; no se realizó una nueva cancelación"
  },
  "error": null
}
```

**Salida mostrada al usuario:**

```text
Job #1 ya estaba cancelado; no se realizó una nueva cancelación
```

**c) El trabajo ya terminó**

**Respuesta de error del demonio:**

```json
{
  "protocol_version": "0.0.1",
  "status": "error",
  "data": null,
  "error": {
    "message": "No se puede cancelar el Job #1: ya está terminado (estado: Succeeded). Consulta 'status 1' para ver su resultado"
  }
}
```

**Salida mostrada al usuario:**

```text
Error: No se puede cancelar el Job #1: ya está terminado (estado: Succeeded). Consulta 'status 1' para ver su resultado
```

**d) El trabajo no existe**

**Respuesta de error del demonio:**

```json
{
  "protocol_version": "0.0.1",
  "status": "error",
  "data": null,
  "error": {
    "message": "No se puede cancelar el Job #1: no encontrado (no existe un trabajo con ese ID). Usa 'status' para ver los IDs disponibles"
  }
}
```

**Salida mostrada al usuario:**

```text
Error: No se puede cancelar el Job #1: no encontrado (no existe un trabajo con ese ID). Usa 'status' para ver los IDs disponibles
```

**e) Identificador inválido**

Si el identificador no es un número entero válido, el cliente muestra:

```text
Error de sintaxis: El ID debe ser un entero
```

**f) Falta el identificador**

Si no se proporciona el identificador, el cliente muestra:

```text
Error de sintaxis: cancel requiere un ID
```

Cuando se cancela un trabajo que estaba ejecutándose, el demonio solicita la terminación de su grupo de procesos mediante el mecanismo de cancelación. Si estaba en espera, lo retira de la cola.

Después de una cancelación exitosa, el demonio intenta despachar otro trabajo pendiente si existe capacidad disponible.

### 5.5. Estado del servidor (health)

La operación `health` permite consultar el estado actual del demonio y algunos datos de su funcionamiento.

**Sintaxis en la CLI:**

```bash
speedyg health
```

No recibe argumentos.

**Petición enviada al demonio:**

```json
{
  "protocol_version": "0.0.1",
  "operation": "health",
  "data": {}
}
```

**Respuesta del demonio:**

```json
{
  "protocol_version": "0.0.1",
  "status": "ok",
  "data": {
    "status": "active",
    "service_version": "1.0.0-rc1",
    "uptime_seconds": 3600,
    "running": 2,
    "queued": 1,
    "queue_capacity": 3
  },
  "error": null
}
```

**Salida mostrada al usuario:**

```text
status=active
service_version=1.0.0-rc1
uptime_seconds=3600
running=2
queued=1
queue_capacity=3
```

**Descripción de los campos:**

- `status`: indica el estado del servicio.
- `service_version`: versión del servicio.
- `uptime_seconds`: tiempo transcurrido desde que inició el demonio, expresado en segundos.
- `running`: cantidad de trabajos en ejecución.
- `queued`: cantidad de trabajos en espera.
- `queue_capacity`: capacidad máxima de la cola de espera.

### 5.6. Comandos speedyG disponibles (help)

La operación `help` permite consultar la lista de comandos speedyG disponibles.

**Sintaxis en la CLI:**

```bash
speedyg help
```

No recibe argumentos.

**Petición enviada al demonio:**

```json
{
  "protocol_version": "0.0.1",
  "operation": "help",
  "data": {}
}
```

**Respuesta del demonio:**

```json
{
  "protocol_version": "0.0.1",
  "status": "ok",
  "data": {
    "commands": [
      "health",
      "help",
      "list",
      "status [id]",
      "cancel <id>"
    ]
  },
  "error": null
}
```

**Salida mostrada al usuario:**

```text
Comandos speedyG disponibles: health, help, list, status [id], cancel <id>
```

### 6. Manejo de errores

El demonio identifica los errores que pueden producirse durante la recepción, validación y procesamiento de las peticiones

Cuando el error ocurre durante el procesamiento de una petición válida, el demonio devuelve una respuesta JSON con estado `error` y un mensaje que describe el problema

Los mensajes mostrados al usuario en la CLI mantienen un formato legible

#### 6.1. Errores de sintaxis y argumentos

Se producen cuando una petición contiene argumentos incorrectos o no cumple con las reglas de la operación solicitada.

**Ejemplos:**

| Petición en la CLI | Mensaje mostrado al usuario |
|---|---|
| `speedyg health extra` | `Error de sintaxis: health no recibe argumentos` |
| `speedyg cancel` | `Error de sintaxis: cancel requiere un ID` |
| `speedyg cancel abc` | `Error de sintaxis: El ID debe ser un entero` |
| `speedyg status 1 2` | `Error de sintaxis: status solo acepta un argumento opcional (ID o estado)` |
| `speedyg list extra` | `Error de sintaxis: list no recibe argumentos` |
| `speedyg status abc` | `Error de sintaxis: El argumento de status debe ser un ID entero o un estado válido (queued, running, succeeded, failed, canceled, interrupted)` |
| `speedyg help extra` | `Error de sintaxis: help no recibe argumentos` |

#### 6.2. Errores por límites del mensaje y argumentos

El demonio valida el tamaño de los mensajes recibidos y limita la cantidad de argumentos y el tamaño individual de cada uno.

**Ejemplos:**

| Condición | Mensaje mostrado al usuario |
|---|---|
| Mensaje que supera el tamaño máximo permitido | `Error: el mensaje supera el tamanio maximo permitido.` |
| Mensaje con codificación UTF-8 inválida | `Error: mensaje rechazado por formato UTF-8 invalido. Envia texto valido.` |
| Comando que supera el máximo de argumentos | `Error de sintaxis: El comando supera el máximo de 32 argumentos` |
| Argumento que supera el tamaño máximo permitido | `Error de sintaxis: El argumento '...' supera el máximo de 256 bytes` |

Los límites predeterminados son:

- Tamaño máximo del mensaje: 65 536 bytes
- Cantidad máxima de argumentos: 32
- Tamaño máximo por argumento: 256 bytes

#### 6.3. Errores relacionados con los trabajos

Se producen cuando un trabajo no existe, ya terminó o no puede agregarse a la cola.

**Ejemplos:**

| Condición | Mensaje mostrado al usuario |
|---|---|
| La cola está llena | `Error al enviar 'sleep': la cola está llena (capacidad: 3). Espera a que se libere un espacio` |
| Se consulta un ID inexistente | `Error: Job #1 no encontrado` |
| Se intenta cancelar un trabajo inexistente | `Error: No se puede cancelar el Job #1: no encontrado (no existe un trabajo con ese ID). Usa 'status' para ver los IDs disponibles` |
| Se intenta cancelar un trabajo que ya terminó | `Error: No se puede cancelar el Job #1: ya está terminado (estado: Succeeded). Consulta 'status 1' para ver su resultado` |

La capacidad de la cola corresponde únicamente a los trabajos en espera; no incluye los trabajos que están en ejecución.

#### 6.4. Errores de conexión y acceso

Se producen cuando un cliente no puede establecer comunicación con el demonio o cuando el servicio no puede aceptar nuevas peticiones

**Comportamiento:**

| Condición | Respuesta o comportamiento |
|---|---|
| Cliente TCP cuya IP no está autorizada | El demonio cierra la conexión sin enviar una respuesta |
| El demonio se está apagando y recibe una nueva conexión | `Error: El demonio se esta apagando, no se aceptan nuevos comandos.` |
| El cliente intenta conectarse cuando el demonio no está ejecutándose | El cliente muestra un mensaje indicando que el demonio no está en ejecución y termina con código de salida 1 |

La autorización de clientes TCP se realiza mediante una lista de direcciones IP permitidas (`tcp_allowlist`)

#### 6.5. Desconexiones y errores de comunicación

El protocolo contempla los siguientes comportamientos ante interrupciones de la comunicación:

- **Cliente desconectado antes de enviar un mensaje:** si el demonio recibe EOF sin datos, termina de procesar esa conexión sin ejecutar ningún comando
- **Cliente desconectado después de enviar un mensaje completo:** si los datos recibidos forman un mensaje válido, el demonio lo procesa aunque no se haya recibido un salto de línea final
- **Mensaje incompleto terminado por EOF:** el demonio intenta procesar los datos recibidos como el último mensaje. Si no forman un mensaje JSON válido, se rechaza la petición
- **Error durante la escritura de la respuesta:** el demonio registra el error y termina el procesamiento de esa conexión

#### 6.6. Lecturas y escrituras parciales

La comunicación utiliza operaciones de lectura y escritura asíncronas para intercambiar mensajes entre el cliente y el demonio.

- **Lecturas parciales:** el demonio acumula los datos recibidos hasta encontrar un salto de línea (`\n`) o hasta que se cierre el flujo de escritura del cliente (EOF)
- **Escrituras parciales:** el cliente y el demonio utilizan `write_all`, que continúa escribiendo los datos hasta completar el envío o producir un error
- **Delimitación:** cada mensaje se procesa una vez que se recibe su delimitador o se alcanza EOF

## 7. Versionado del protocolo

El protocolo utiliza **Semantic Versioning (SemVer)** para identificar la versión de las reglas de comunicación entre el cliente y el demonio.

La versión del protocolo es independiente de la versión del servicio:

- **Versión del servicio:** identifica la versión del programa speedyG
- **Versión del protocolo:** identifica la versión de las reglas utilizadas para intercambiar mensajes

La versión inicial del protocolo será `0.0.1`.

Cada mensaje enviado, tanto por el cliente como por el demonio, deberá incluir la versión del protocolo correspondiente.

El receptor deberá comprobar la versión recibida para determinar si es compatible con la que utiliza. Este mecanismo no requiere un handshake ni una negociación previa entre el cliente y el demonio.

### 7.1. Compatibilidad de versiones

El receptor verifica que la versión del protocolo incluida en cada mensaje coincida exactamente con la versión que soporta. Para esta versión del protocolo, únicamente se acepta `0.0.1.`

Si la versión recibida no es compatible, el mensaje será rechazado y se devolverá un error que indique la incompatibilidad

No se realiza una negociación de versiones ni se cambia automáticamente a otra versión del protocolo

### 8. Límites y capacidades

El servicio establece los siguientes límites para controlar el procesamiento de peticiones y la ejecución de trabajos.

| Parámetro | Valor predeterminado | Descripción |
|---|---:|---|
| Tamaño máximo del mensaje | 65 536 bytes | Tamaño máximo permitido por mensaje recibido |
| Cantidad máxima de argumentos | 32 | Número máximo de argumentos por comando, sin contar el nombre del programa |
| Tamaño máximo por argumento | 256 bytes | Cantidad máxima de bytes permitidos por argumento |
| Capacidad de la cola | 3 trabajos | Cantidad máxima de trabajos en espera |
| Trabajos simultáneos | 3 trabajos | Cantidad máxima de trabajos que pueden ejecutarse al mismo tiempo |
| Conexiones simultáneas | 2 clientes | Cantidad máxima de conexiones de clientes activas |

Los límites pueden modificarse mediante los argumentos de configuración o las variables de entorno correspondientes, cuando exista una opción de configuración para ello.

**Conexiones de clientes:**

El demonio acepta conexiones mediante Unix Domain Socket y TCP. Se permite un máximo de 2 conexiones simultáneas. Las conexiones adicionales serán rechazadas.