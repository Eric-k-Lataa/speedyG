# ADR-06: Protocolo de Red

## Contexto

Actualmente el daemon de SpeedyG (`src/main.rs`) escucha únicamente en un *Unix Domain Socket* local (`/tmp/speedyg.sock`) mediante `UnixStream`, mientras que el cliente efímero (`src/bin/speedyg.rs`) envía peticiones de forma puntual desde la terminal. Cada conexión realiza una única lectura de hasta 1024 bytes sin delimitación de mensajes ni campo de versión del protocolo.

Para el Hito 3 es necesario definir de forma pragmática y factible en poco tiempo cómo evolucionará la comunicación hacia red (manteniendo la misma semántica operativa de `RF-19` entre el socket Unix local y el listener TCP), cómo se delimitan y acotan los mensajes sobre flujos de bytes (*framing* y tamaño máximo), y cómo se versiona el protocolo sin añadir complejidad innecesaria de sesión.

## Alternativas consideradas

### Mantener únicamente Unix Domain Socket + túnel SSH manual

**Ventajas:**
- Reutiliza íntegramente el transporte local existente sin abrir puertos TCP directos en el daemon
- Se apoya en el cifrado y autenticación estándar de SSH si se requiere acceso remoto

**Desventajas:**
- No incorpora un listener TCP nativo en el daemon si se exige configurar y probar coexistencia TCP/Unix
- Requiere que el operador levante y administre el túnel SSH por fuera del servicio

### TCP plano (sin TLS) + prefijo de longitud binario (`u32`) + handshake de versión

**Ventajas:**
- El prefijo de longitud fijo facilita calcular el tamaño exacto del payload antes de leerlo
- Un *handshake* inicial evita repetir metadatos de versión en conexiones con múltiples mensajes

**Desventajas:**
- Un formato binario requiere herramientas o utilidades específicas para inspeccionar o depurar tramas en terminal
- Un *handshake* añade ida y vuelta y estado de conexión innecesario para comandos puntuales sin sesión interactiva

### Coexistencia Unix Domain Socket + Listener TCP (con túnel SSH) + JSON delimitado por línea (`NDJSON`) + versión por mensaje (sin handshake)

**Ventajas:**
- Mantiene el socket Unix local y habilita el listener TCP enrutando ambos hacia el mismo despachador/controlador (`RF-19`)
- Reutiliza prototipos JSON existentes y delimita mensajes de forma clara mediante salto de línea (`\n`), con límite estricto de 64 KiB (65 536 bytes) y campo de versión SemVer en cada mensaje
- Evita *handshake* previo y evita implementar TLS o túneles automáticos complejos dentro del código, cumpliendo el alcance en poco tiempo

**Desventajas:**
- Requiere escapar correctamente saltos de línea dentro de campos JSON y usar lectura acumulada con búfer en lugar de lecturas fijas de 1024 bytes
- Depender de túnel SSH para el tráfico TCP implica que la seguridad del canal remoto recae en la configuración externa del túnel

## Decisión

Se selecciona **Coexistencia de Unix Domain Socket + Listener TCP (mediante túnel SSH), framing con JSON delimitado por línea (`\n`), límite máximo de 64 KiB por mensaje y versión SemVer en cada mensaje (sin handshake)**.

Esta decisión se toma porque permite cumplir los criterios del Hito 3 de forma rápida y realista: aprovecha la base de *Unix Domain Socket* y los prototipos JSON ya presentes, garantiza la misma semántica entre el transporte local y TCP (`RF-19`), acota el consumo de memoria con un límite de 64 KiB antes de aceptar payloads desmedidos, y mantiene cada petición autocontenida con su versión sin introducir el *overhead* de un *handshake* ni la complejidad de gestionar certificados TLS o túneles automáticos desde el daemon.

## Consecuencias

### Alternativas consideradas

#### Mantener únicamente Unix Domain Socket + túnel SSH manual

**Positivas**
- Mínimo cambio sobre el transporte local ya operativo

**Negativas**
- No cubre de forma nativa el listener TCP ni su coexistencia explícita con el socket Unix

**Riesgos**
- Quedarse corto frente a los criterios de aceptación que piden decisión explícita sobre TCP y coexistencia (`RF-19`)

#### TCP plano (sin TLS) + prefijo de longitud binario (`u32`) + handshake de versión

**Positivas**
- Lectura de longitud conocida y menor repetición de cabecera en conexiones persistentes

**Negativas**
- Menor legibilidad directa en pruebas manuales y mayor estado de conexión por el *handshake*

**Riesgos**
- Errores de desincronización de estado de sesión o pérdida de tiempo depurando tramas binarias y *handshakes*

#### Coexistencia Unix Domain Socket + Listener TCP (con túnel SSH) + JSON delimitado por línea (`NDJSON`) + versión por mensaje (sin handshake) (Seleccionada)

**Positivas**
- Misma lógica y semántica de ejecución tanto en Unix socket como en TCP (`RF-19`)
- Mensajes autocontenidos con versión (p. ej. `major.minor`) que permiten rechazar incompatibilidades de forma limpia sin tumbar el daemon ni requerir *handshake*
- Límite de 64 KiB que previene lecturas ilimitadas y *buffer bloat* sin bloquear comandos habituales del *jobrunner*

**Negativas**
- Exige actualizar la lectura en el daemon (`src/main.rs`), el parseo/validación de versión (`src/parser.rs`) y el empaquetado en el CLI (`src/bin/speedyg.rs`)
- El canal TCP asume uso con túnel SSH para proteger el transporte remoto, sin cifrado TLS nativo en el daemon

**Riesgos**
- Exponer el puerto TCP directamente a una red no confiable sin túnel SSH ni restricción de interfaz/firewall dejaría el tráfico sin cifrado ni autenticación a nivel de transporte
- Líneas sin `\n` o payloads malformados podrían provocar cierres de conexión o errores de parseo si no se validan antes de procesar

## Requisitos afectados

### Alternativas consideradas

#### Mantener únicamente Unix Domain Socket + túnel SSH manual
- `+RF-19` : Conserva el comportamiento local existente sin duplicar flujos
- `-RF-19` : No define la coexistencia explícita con el listener TCP

- `+RNF-32` : Permite evolucionar el formato del mensaje en el socket local
- `-RNF-34` : Deja sin resolver el análisis de exposición y transporte TCP exigido por el Hito 3

#### TCP plano (sin TLS) + prefijo de longitud binario (`u32`) + handshake de versión
- `+RF-19` : Soporta transporte TCP para operaciones remotas
- `-RF-19` : El *handshake* añade complejidad de estado entre conexiones local y TCP

- `+RNF-29` : El prefijo de longitud ayuda a acotar lecturas por trama
- `-RNF-32` : Mayor fricción al validar y depurar versiones en tramas binarias

#### Coexistencia Unix Domain Socket + Listener TCP (con túnel SSH) + JSON delimitado por línea (`NDJSON`) + versión por mensaje (sin handshake)
- `+RF-19` : Unifica el despacho del daemon sobre Unix socket y TCP con la misma semántica operativa
- `+RNF-29` : Delimitación por `\n` y límite de 64 KiB previenen lecturas truncadas de 1024 bytes y desbordamientos de búfer
- `+RNF-32` : Incluye versión SemVer en cada mensaje para detectar y rechazar versiones incompatibles de forma explícita
- `+RNF-34` : Documenta el uso de túnel SSH para el transporte TCP y registra el riesgo de exposición sin TLS en el ADR

### Evidencia y prototipo de referencia
- Estado actual del repositorio: daemon en `src/main.rs` escuchando en `/tmp/speedyg.sock` con lectura única de 1024 bytes, cliente CLI en `src/bin/speedyg.rs`, lógica de análisis en `src/parser.rs` y prototipos JSON existentes en el proyecto.
