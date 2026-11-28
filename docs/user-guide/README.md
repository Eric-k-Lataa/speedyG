# Guía de usuario

speedyG es un servicio (*daemon*) para Linux que ejecuta comandos como **trabajos**: los pones en una cola, los consultas, los listas y, si hace falta, los cancelas. Esta guía te lleva de cero a tu primer trabajo sin ayuda del equipo.

## 1. Requisitos

- Debian (probado en Debian 13, kernel 6.12) o distribución Linux equivalente.
- Rust y Cargo (instalados con `rustup`).
- Git.
- No necesitas permisos de administrador para ejecutar SpeedyG. La instalación de dependencias del sistema sí requiere permisos de administrador.

## 2. Instalación

```bash
# Herramientas de compilación
sudo apt update
sudo apt install -y build-essential git curl pkg-config

# Solo si la compilación se queja de SQLite:
sudo apt install -y libsqlite3-dev

# Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"

# Código y compilación
git clone https://github.com/Eric-k-Lataa/speedyG.git
cd speedyG
cargo build
cargo test
```
### Instalación de los ejecutables

Desde el directorio del repositorio, instala los ejecutables para poder utilizar `speedyG` y `speedyg` directamente, sin anteponer `cargo run`:

```bash
cargo install --path . 
```
Los ejecutables quedan instalados en ~/.cargo/bin. Asegúrate de que este directorio esté incluido en tu variable PATH.

Se generan dos programas en `target/debug/`:

| Programa | Qué es |
| --- | --- |
| `speedyG` | El servicio (daemon), encargado de gestionar y ejecutar los trabajos |
| `speedyg` | El cliente CLI, utilizado para enviar comandos al servicio |

> Ojo con las mayúsculas: `speedyG` (servicio) y `speedyg` (cliente) son programas distintos.

## 3. Iniciar el servicio

En una terminal:

```bash
speedyG
```

Debes ver una línea parecida a: `Demonio speedyG escuchando en /tmp/speedyg.sock`. **Deja esa terminal abierta**; para detener el servicio presiona `Ctrl+C`.

Comprueba que responde (en otra terminal):

```bash
speedyg health
```

Resultado esperado: una respuesta de varias líneas con el resumen de salud del servicio; la primera línea es `status=active`:

```text
status=active
service_version=<versión>
uptime_seconds=<segundos desde el arranque>
running=<trabajos en ejecución>
queued=<trabajos en cola>
queue_capacity=<capacidad máxima de la cola>
```

Para consultar los comandos disponibles: 
```bash
speedyg help
```

### Conexión desde otro equipo

SpeedyG también contempla conexiones mediante TCP para permitir que otros equipos de una red privada o VPN utilicen el servicio.

Para habilitarlas, el administrador debe configurar:

- `tcp_enabled`: habilita el servicio TCP.
- `tcp_host`: dirección IP de escucha. Por defecto, `127.0.0.1`.
- `tcp_port`: puerto de escucha. Por defecto, `7878`.
- `tcp_allowlist`: direcciones IP autorizadas para conexiones no locales.

Cuando `tcp_host` utiliza una dirección distinta de `127.0.0.1`, es obligatorio configurar `tcp_allowlist` con las direcciones IP autorizadas.

El equipo cliente debe encontrarse en la red permitida y utilizar la dirección y el puerto configurados en el servicio.

Se recomienda no exponer el servicio directamente a Internet.


## 4. Enviar un trabajo

```bash
speedyg echo hola
```

Respuesta esperada: `Job #7 encolado correctamente`. El número es el **ID del trabajo**: anótalo, lo necesitas para consultarlo o cancelarlo.

Trabajo de varios segundos, para practicar:

```bash
speedyg sleep 30
```

## 5. Consultar el estado

```bash
speedyg status 7
```

Ejemplos de respuesta:

```text
Job #8: sleep 10 [Running]
Job #8: sleep 10 [Succeeded] (exit code: 0)
```

La consulta muestra el estado del trabajo y, cuando está disponible, su código de salida y resultado de ejecución. La salida almacenada tiene un límite de 1.000.000 de bytes por trabajo. Si se supera, el contenido excedente se descarta y se indica que la salida fue truncada.

## 6. Listar trabajos

```bash
speedyg list
```

Muestra el ID y el estado de cada trabajo registrado.

## 7. Cancelar un trabajo

```bash
speedyg cancel 8 
```

- Si el trabajo está **en cola**, se marca como cancelado, y aunque termine, el resultado es ignorado.
- Si dos personas cancelan a la vez, ambas reciben una respuesta clara y el trabajo queda en un único estado final. No se puede cancelar algo ya cancelado por otra terminal

### Estados posibles

| Estado | Significado |
| --- | --- |
| `Queued` | Aceptado y esperando su turno |
| `Running` | Ejecutándose |
| `Succeeded` | Terminó con código de salida 0 |
| `Failed` | Terminó con error (código distinto de 0 o por señal) |
| `Canceled` | Fue cancelado |
| `Interrupted` | El servicio se reinició mientras el trabajo estaba en ejecución, por lo que ya no se controla |

Los estados `Succeeded`, `Failed`, `Canceled` e `Interrupted` son **finales**: no cambian.

## 8. Mensajes y su significado

### 8.1 Catálogo

| Situación | Mensaje (orientativo) | Significado | Qué hacer |
| --- | --- | --- | --- |
| Trabajo aceptado | `Job #N encolado correctamente` | El trabajo quedó registrado con ese ID | Guarda el ID |
| Servicio activo | `status=active` (seguido de versión, uptime, trabajos en ejecución, en cola y capacidad de la cola) | El servicio responde | Nada |
| Estado de un trabajo | `Job #N: <comando> [<Estado>]` | Estado actual | Nada |
| Comando vacío o mal formado | rechazo con la causa | La solicitud no es válida | Revisa la sintaxis |
| No se puede conectar | error de conexión al socket | El servicio no está corriendo, o el socket no existe | Inicia el servicio (sección 3) |
| Job inexistente | mensaje de "no existe" | Job no encontrado | Revisa el ID con `status` |
| Cancelar un job ya terminado | mensaje de "ya terminó" | No hay nada que cancelar | Consulta su estado |


## 9. Problemas frecuentes

| Problema | Causa probable | Solución |
| --- | --- | --- |
| `Address already in use` o el servicio no arranca | Puede existir otra instancia del servicio o un socket residual | Comprueba si hay otro servicio (`pgrep -a speedyG`). Si no está ejecutándose, elimina el socket residual (`rm /tmp/speedyg.sock`) e intenta iniciar nuevamente |
| El cliente no conecta | Servicio detenido | Inicia el servicio |
| Un trabajo se queda en `Queued` | Se alcanzó el límite de concurrencia | Espera a que termine alguno o súbe en la configuración |
| El comando `speedyg` no se reconoce | Los ejecutables no están instalados o `~/.cargo/bin` no está en `PATH` | Ejecuta `cargo install --path .` desde el repositorio y verifica la variable `PATH` |

## 10. Cerrar y recuperar el servicio

Para detener el servicio de forma controlada, presiona `Ctrl+C` en la terminal donde se está ejecutando.

- Los trabajos en ejecución reciben una solicitud de cancelación.
- Los trabajos en cola pueden comenzar si se libera capacidad antes de que termine el servicio.
- Si el servicio se cierra mientras todavía hay trabajos en ejecución, estos se recuperan como `Interrupted` al iniciar nuevamente.
- Los trabajos que permanecían en cola se conservan para continuar su ejecución después de la recuperación.

Si la terminal se cierra inesperadamente, los trabajos que estaban en ejecución se recuperan como `Interrupted`, mientras que los que estaban en cola se conservan.

Para recuperar el servicio, vuelve a iniciarlo:

```bash
speedyG
```

## 11. Prueba con una persona ajena (RNF-23)

Para cerrar el issue #83 hace falta que alguien ajeno al equipo siga **solo esta guía**. Anota aquí el resultado:

| Campo | Valor |
| --- | --- |
| Persona | Alberto Mancillas M |
| Fecha | 30-10-2026 |
| ¿Instaló, inició, envió y consultó un trabajo sin ayuda? | Sí |
| Pasos donde se atoró | Algunas ocasiones olvido colocar el comando completo para enviar ordenes al Daemon o problemas con la g|
| Correcciones aplicadas | Marcar la diferencia entre g y G. |

