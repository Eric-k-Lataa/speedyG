Cadena obligatoria: Requisito → Método → Caso → Resultado esperado → Evidencia → PASS/FAIL.

**Estados de resultado:** `PASS` · `FAIL` · `BLOCKED` · `Pendiente` (caso sin ejecución real).
Un caso solo pasa a `PASS` con una corrida real y evidencia en `verif/results/<TC>/<run-id>/`.

**Notas:**
- Los casos TC-001…TC-024 siguen la numeración del Plan de Verificación (`context/05`).
- `(propuesto)` indica un caso o método que el plan oficial no asigna a ese requisito y que el equipo debe confirmar.
- `Inspección` significa que no hay script; la evidencia es el archivo o documento revisado.

## Requisitos funcionales

| Req ID | Descripción breve | Prioridad | Método | Caso(s) | Evidencia | Resultado | Defecto/Excepción |
|:-------|:------------------|:---------:|:------:|:--------|:----------|:---------:|:------------------|
| RF-01 | Enviar trabajo e ID único | Alta | Prueba | TC-001 | resultado + log | PASS | — |
| RF-02 | Validar solicitud con mensaje útil | Alta | Prueba | TC-001 | resultado + log | PASS | — |
| RF-03 | Mantener una cola | Alta | Prueba | TC-002 | status-samples + resumen | PASS | — |
| RF-04 | Procesos independientes | Alta | Prueba | TC-001, TC-002 | estados + log | PASS | — |
| RF-05 | Límite de concurrencia | Alta | Prueba | TC-002 | timeline + ps/log | PASS | — |
| RF-06 | Estados de un trabajo | Alta | Prueba | TC-003 | timeline + log | Pendiente | — |
| RF-07 | Registrar tiempos y código de salida | Alta | Prueba | TC-003, TC-006 | resultado + log | Pendiente | — |
| RF-08 | Consultar estado y metadatos por ID | Alta | Prueba | TC-004 | estados + log | Pendiente | — |
| RF-09 | Listar trabajos con filtro por estado | Alta | Prueba | TC-004 | estados + log | Pendiente | — |
| RF-10 | Cancelar en cola o en ejecución | Alta | Prueba | TC-005 | estados + señal | Pendiente | — |
| RF-11 | Capturar y consultar stdout y stderr por separado | Alta | Prueba | TC-006 | resultado + log | Pendiente | — |
| RF-12 | Conservar metadatos tras reiniciar | Alta | Prueba | TC-007 | resultado + log | Pendiente | — |
| RF-13 | Recuperar historial y marcar interrumpidos al arrancar | Alta | Prueba | TC-007 | resultado + log | Pendiente | — |
| RF-14 | Bitácora de eventos con marca temporal e ID de trabajo | Alta | Prueba/Inspección | TC-020 (propuesto) | daemon.log | Pendiente | — |
| RF-15 | Inicio y cierre controlados, sin aceptar trabajos al cerrar | Alta | Prueba | TC-009 | resultado + log | Pendiente | — |
| RF-16 | Configuración: directorio de datos, límite, interfaz y puerto | Alta | Prueba/Inspección | TC-013 | log de arranque + stderr con `SPEEDYG_QUEUE_CAP=0` | Pendiente | — |
| RF-17 | Ayuda de uso y códigos de salida del cliente | Alta | Prueba/Inspección | TC-015 | salida de `help` + códigos | Pendiente | — |
| RF-18 | Operación remota con protocolo documentado | Alta | Prueba/Demo | TC-010 | cliente y servidor | Pendiente | — |
| RF-19 | Misma semántica local y remota | Alta | Prueba/Demo | TC-010 | cliente y servidor | Pendiente | — |
| RF-20 | Solo LAN/VPN autorizada | Crítica | Prueba/Análisis | TC-011 | configuración + intento | Pendiente | — |
| RF-21 | Protocolo delimitado, tolera lecturas/escrituras parciales | Alta | Prueba | TC-012 | resultado + log | Pendiente | — |
| RF-22 | Desconexión de cliente sin afectar servicio ni trabajos | Alta | Prueba | TC-012, TC-019 | resultado + log | Pendiente | — |
| RF-23 | Rechazar y registrar solicitudes que excedan límites | Crítica | Prueba | TC-016 | rejection.txt + daemon.log | PASS | — |
| RF-24 | Resumen de salud: activo, en ejecución, en cola, errores | Alta | Prueba | TC-013 | salida de `health` | Pendiente | — |
| RF-25 | Rechazo explícito con cola llena, sin bloquear ni perder trabajos | Crítica | Prueba | TC-016 | rejection.txt + status antes/después | PASS | — |
| RF-26 | Cancelaciones concurrentes con estado final coherente | Crítica | Prueba | TC-017 | respuestas + estado final | Pendiente | — |
| RF-27 | Solicitud duplicada sin estados contradictorios | Crítica | Prueba | TC-018 | respuestas + status | Pendiente | — |
| RF-28 | Desconexión durante solicitud con estado coherente | Crítica | Prueba | TC-019 | respuestas + status + log | Pendiente | — |
| RF-29 | Terminación inesperada del hijo: detectar, liberar y registrar | Crítica | Prueba | TC-020 | estados + ps + log | Pendiente | — |
| RF-30 | Escalamiento de cancelación documentado y verificable | Crítica | Prueba | TC-021 | señales + estados + log | Pendiente | — |

## Requisitos no funcionales

| Req ID | Descripción breve | Prioridad | Método | Caso(s) | Evidencia | Resultado | Defecto/Excepción |
|:-------|:------------------|:---------:|:------:|:--------|:----------|:---------:|:------------------|
| RNF-01 | Compilar y ejecutar en Linux declarado | Alta | Prueba | TC-014 | resultado + log | Pendiente | — |
| RNF-02 | Construcción reproducible desde clon limpio | Alta | Prueba/Inspección | TC-014 | log de build | Pendiente | — |
| RNF-03 | Sin privilegios de root | Alta | Prueba | TC-014 | `id -u` + log | Pendiente | — |
| RNF-04 | Con límite 3, al menos 3 trabajos simultáneos | Alta | Prueba | TC-002 | ps-samples + resumen | PASS | — |
| RNF-05 | Consulta de estado ≤ 1 s con 100 trabajos | Alta | Prueba | TC-004 | tiempos medidos | Pendiente | — |
| RNF-06 | Soportar al menos 500 registros sin pérdida | Alta | Prueba | TC-007 (propuesto) | conteo antes/después de reiniciar | Pendiente | — |
| RNF-07 | La cola no inicia más procesos que el límite | Alta | Prueba | TC-002 | ps-samples + resumen | PASS | — |
| RNF-08 | Solicitud inválida o desconexión no termina el servicio | Alta | Prueba | TC-008 | resultado + log | Pendiente | — |
| RNF-09 | Terminación anormal de un trabajo no afecta a otros | Crítica | Prueba | TC-008 | log + estados | Pendiente | — |
| RNF-10 | Tras reiniciar, no reportar RUNNING un proceso no controlado | Alta | Prueba | TC-007 | resultado + log | Pendiente | — |
| RNF-11 | Escritura de archivos persistentes sin estado parcial | Alta | Prueba | TC-007, TC-022 | resultado + log | Pendiente | — |
| RNF-12 | No escuchar en interfaces públicas por defecto | Crítica | Prueba/Inspección | TC-011 | `ss -ltn` + configuración | Pendiente | — |
| RNF-13 | Acceso remoto limitado a localhost, subred privada o VPN | Crítica | Prueba | TC-011 | configuración + intento | Pendiente | — |
| RNF-14 | Validar longitud y formato de mensajes de red | Alta | Prueba | TC-012 | resultado + log | Pendiente | — |
| RNF-15 | Registros sin secretos | Alta | Inspección | revisión de `daemon.log` y código (propuesto) | grep + revisión | Pendiente | — |
| RNF-16 | Mínimo privilegio y modelo de amenazas básico | Alta | Inspección | documento de amenazas (propuesto) | documento | Pendiente | — |
| RNF-17 | Módulos con responsabilidades identificables | Alta | Inspección | revisión de `src/` | estructura del repositorio | Pendiente | — |
| RNF-18 | Interfaces públicas y decisiones documentadas | Alta | Inspección | ADR + guías (propuesto) | documentos | Pendiente | — |
| RNF-19 | Compilar sin advertencias nuevas | Alta | Prueba | TC-014 (propuesto) | log de `cargo build` y `clippy` en CI | Pendiente | — |
| RNF-20 | Pruebas con un único comando documentado | Alta | Prueba | TC-014 (propuesto) | ejecución de `run-all.sh` | Pendiente | — |
| RNF-21 | Errores con operación, causa y acción sugerida | Alta | Prueba | TC-015, TC-016 | mensajes capturados | PASS (TC-016) | — |
| RNF-22 | Bitácora que correlaciona solicitud con trabajo | Alta | Prueba | TC-020 (propuesto) | daemon.log | Pendiente | — |
| RNF-23 | Guía de usuario suficiente sin asistencia | Alta | Prueba/Demo | TC-015 | prueba con un usuario ajeno | Pendiente | — |
| RNF-24 | Protocolo con mensajes fragmentados y solicitudes secuenciales | Alta | Prueba | TC-012 | resultado + log | Pendiente | — |
| RNF-25 | Liberar sockets y procesos hijos al cerrar | Alta | Prueba | TC-009 | ps + ss + log | Pendiente | — |
| RNF-26 | Demostración solo en red privada o VPN | Crítica | Inspección/Demo | TC-010, TC-011 | bind + reglas | Pendiente | — |
| RNF-27 | Transiciones consistentes ante concurrencia, sin regresiones | Crítica | Prueba | TC-017 | estados + log | Pendiente | — |
| RNF-28 | Actualizaciones persistentes atómicas o recuperables | Crítica | Prueba | TC-022 | archivos antes/después + log | Pendiente | — |
| RNF-29 | Backpressure o rechazo explícito en límites | Crítica | Prueba | TC-016 | rejection.txt + recovery.txt | PASS | — |
| RNF-30 | Sin procesos huérfanos tras cierre o falla | Crítica | Prueba | TC-020, TC-009 | ps + log | Pendiente | — |
| RNF-31 | Recuperación distingue pendientes, terminados e interrumpidos | Crítica | Prueba | TC-007, TC-022 | estados antes/después | Pendiente | — |
| RNF-32 | Compatibilidad de versión del protocolo | Alta | Prueba | TC-023 | respuesta a versión incompatible | Pendiente | — |
| RNF-33 | Liberación de memoria, procesos, archivos y sockets bajo estrés | Alta | Prueba | TC-024 | fds + procesos + memoria | Pendiente | — |
| RNF-34 | Decisiones de seguridad/consistencia con análisis de riesgo y prueba | Alta | Inspección | ADR + registro de riesgos (propuesto) | documentos | Pendiente | — |

## Cobertura por caso

| Caso | Título | Requisitos | Script | Estado |
|:-----|:-------|:-----------|:-------|:-------|
| TC-001 | Enviar trabajo válido | RF-01, RF-02, RF-04 | `TC-001.sh` | PASS |
| TC-002 | Cola y límite de concurrencia | RF-03, RF-05, RNF-04, RNF-07 | `TC-002.sh` | PASS |
| TC-003 | Estados y tiempos | RF-06, RF-07 | — | Sin redactar |
| TC-004 | Consultar y listar | RF-08, RF-09, RNF-05 | — | Sin redactar |
| TC-005 | Cancelar en cola y ejecución | RF-10 | — | Sin redactar |
| TC-006 | Capturar stdout/stderr y código | RF-11, RF-07 | — | Sin redactar |
| TC-007 | Reinicio y recuperación | RF-12, RF-13, RNF-06, RNF-10, RNF-11, RNF-31 | — | Sin redactar |
| TC-008 | Aislamiento de fallo | RNF-08, RNF-09 | — | Sin redactar |
| TC-009 | Cierre controlado | RF-15, RNF-25, RNF-30 | — | Sin redactar |
| TC-016 | Saturación de cola y rechazo explícito | RF-23, RF-25, RNF-21, RNF-29 | `TC-016.sh` | PASS |
| TC-017 | Cancelaciones concurrentes | RF-26, RNF-27 | — | Sin redactar |
| TC-018 | Solicitud duplicada | RF-27 | — | Sin redactar |
| TC-020 | Terminación inesperada del hijo | RF-14, RF-29, RNF-22, RNF-30 | — | Sin redactar |
| TC-021 | Escalamiento de cancelación | RF-30 | — | Sin redactar |
| TC-022 | Interrupción durante persistencia | RNF-11, RNF-28, RNF-31 | — | Sin redactar |
| TC-024 | Liberación de recursos bajo carga | RNF-33 | — | Sin redactar |

Los TC-010 a TC-015, TC-019 y TC-023 aparecen en la matriz pero aún no tienen archivo ni script. Hay que confirmar con el equipo cuáles entran en este avance. TC-019 (RF-28) sí lo exige el brief del Avance 02.

## Decisiones pendientes

1. **RNF-06** (500 registros): el plan oficial no define caso. Se propone cubrirlo dentro de TC-007.
2. **RF-14, RNF-22** (bitácora): el plan oficial no define caso. Se propone evaluar `daemon.log` dentro de TC-016 y TC-020.
3. **RNF-15, RNF-16, RNF-17, RNF-18, RNF-34**: son de inspección documental; falta decidir qué documento sirve de evidencia.
4. **RNF-19, RNF-20**: se propone cubrirlos con el CI (`clippy` y `run-all.sh`).
5. **TC-019** no tiene redactor asignado.
