# Guía de usuario

speedyG es un servicio (*daemon*) para Linux que ejecuta comandos como **trabajos**: los pones en una cola, los consultas, los listas y, si hace falta, los cancelas. Esta guía te lleva de cero a tu primer trabajo sin ayuda del equipo.

## 1. Requisitos

- Debian (probado en Debian 13, kernel 6.12) o distribución Linux equivalente.
- Rust y Cargo (instalados con `rustup`).
- Git.
- No necesitas ser root.

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

Se generan dos programas en `target/debug/`:

| Programa | Qué es |
| --- | --- |
| `speedyG` | El **servicio** (daemon). Se despierta el Daemon y escucha |
| `speedyg` | El **cliente**: el comando para enviar ordenes a daemon |

> Ojo con las mayúsculas: `speedyG` (servicio) y `speedyg` (cliente) son programas distintos.

## 3. Iniciar el servicio

En una terminal:

```bash
cargo run --bin speedyG
```

Debes ver una línea parecida a: `Demonio speedyG escuchando en /tmp/speedyg.sock`. **Deja esa terminal abierta**; para detener el servicio presiona `Ctrl+C`.

Comprueba que responde (en otra terminal):

```bash
cargo run --bin speedyg -- health
```

Resultado esperado: `OK: Daemon speedyg funcionando correctamente`.

> **Sobre `--`:** al usar `cargo run`, lo que va después de `--` se entrega al programa.

Para consultar los comandos disponibles: 
```bash
cargo run --bin speedyg -- help
```
## 4. Enviar un trabajo

```bash
cargo run --bin speedyg -- echo hola
```

Respuesta esperada: `Job #7 encolado correctamente`. El número es el **ID del trabajo**: anótalo, lo necesitas para consultarlo o cancelarlo.

Trabajo de varios segundos, para practicar:

```bash
cargo run --bin speedyg -- sleep 30
```

## 5. Consultar el estado

```bash
cargo run --bin speedyg -- status 7
```

Ejemplos de respuesta:

```text
Job #8: sleep 10 [Running]
Job #8: sleep 10 [Succeeded] (exit code: 0)
```

## 6. Listar trabajos

```bash
cargo run --bin speedyg -- list
```

Muestra el ID y el estado de cada trabajo registrado.

## 7. Cancelar un trabajo

```bash
cargo run --bin speedyg -- cancel 8 
```

- Si el trabajo está **en cola**, se marca como cancelado, y aunque termine el resultado es ignorado.
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
| Servicio activo | `OK: Daemon speedyg funcionando correctamente` | El servicio responde | Nada |
| Estado de un trabajo | `Job #N: <comando> [<Estado>]` | Estado actual | Nada |
| Comando no autorizado | rechazo con la causa (ej. `rm archivo.txt`) | La política prohíbe ese comando | Usa un comando permitido |
| Comando vacío o mal formado | rechazo con la causa | La solicitud no es válida | Revisa la sintaxis |
| No se puede conectar | error de conexión al socket | El servicio no está corriendo, o el socket no existe | Inicia el servicio (sección 3) |
| Job inexistente | mensaje de "no existe" | Job no encontrado | Revisa el ID con `status` |
| Cancelar un job ya terminado | mensaje de "ya terminó" | No hay nada que cancelar | Consulta su estado |


## 9. Problemas frecuentes

| Problema | Causa probable | Solución |
| --- | --- | --- |
| `Address already in use` o el servicio no arranca | Quedó un socket de una ejecución anterior | Comprueba que no haya otro servicio (`pgrep speedyG`) y borra el socket (`rm /tmp/speedyg.sock`) |
| El cliente no conecta | Servicio detenido | Inicia el servicio |
| Un trabajo se queda en `Queued` | Se alcanzó el límite de concurrencia | Espera a que termine alguno o súbe en la configuración |
| Mucho texto de compilación al usar `cargo run` | Cargo recompila | Usa `./target/debug/speedyg ...` |

## 10. Prueba con una persona ajena (RNF-23)

Para cerrar el issue #83 hace falta que alguien ajeno al equipo siga **solo esta guía**. Anota aquí el resultado:

| Campo | Valor |
| --- | --- |
| Persona | Alberto Mancillas M |
| Fecha | 30-10-2026 |
| ¿Instaló, inició, envió y consultó un trabajo sin ayuda? | Sí |
| Pasos donde se atoró | Algunas ocasiones olvido colocar el comando completo para enviar ordenes al Daemon o problemas con la g|
| Correcciones aplicadas | Marcar la diferencia entre g y G. |

