## Requisitos funcionales

| Req ID | Descripción breve | Prioridad | Método | Caso(s) | Evidencia | Resultado | Defecto/Excepción |
|:-------|:------------------|:---------:|:------:|:--------|:----------|:---------:|:------------------|
| RF-01 | Enviar trabajo e ID único | Alta | Prueba | TC-001 | resultado + log | PASS | N/A |
| RF-02 | Validar solicitud con mensaje útil | Alta | Prueba | TC-001 | resultado + log | PASS | N/A |
| RF-03 | Mantener una cola | Alta | Prueba | TC-002 | status-samples + resumen | PASS | N/A |
| RF-04 | Procesos independientes | Alta | Prueba | TC-001, TC-002 | estados + log | PASS | N/A |
| RF-05 | Límite de concurrencia | Alta | Prueba | TC-002 | timeline + ps/log | PASS | N/A |
| RF-06 | Estados de un trabajo | Alta | Prueba | TC-003 | timeline + log | PASS | N/A |
| RF-07 | Registrar tiempos y código de salida | Alta | Prueba | TC-003, TC-006 | resultado + log | PASS | N/A |
| RF-08 | Consultar estado y metadatos por ID | Alta | Prueba | TC-004 | estados + log | PASS | N/A |
| RF-09 | Listar trabajos con filtro por estado | Alta | Prueba | TC-004 | estados + log | PASS | N/A |
| RF-10 | Cancelar en cola o en ejecución | Alta | Prueba | TC-005 | estados + señal | PASS | N/A |
| RF-11 | Capturar y consultar stdout y stderr por separado | Alta | Prueba | TC-006 | resultado + log | PASS | N/A |
| RF-12 | Conservar metadatos tras reiniciar | Alta | Prueba | TC-007 | resultado + log | PASS | N/A |
| RF-13 | Recuperar historial y marcar interrumpidos al arrancar | Alta | Prueba | TC-007 | resultado + log | PASS | N/A |
| RF-14 | Bitácora de eventos con marca temporal e ID de trabajo | Alta | Prueba/Inspección | TC-020 (propuesto) | daemon.log | Pendiente | Esperando a Paola |
| RF-15 | Inicio y cierre controlados, sin aceptar trabajos al cerrar | Alta | Prueba | TC-009 | resultado + log | Pendiente | Esperando a Uriel |
| RF-16 | Configuración: directorio de datos, límite, interfaz y puerto | Alta | Prueba/Inspección | TC-013 | log de arranque + stderr con `SPEEDYG_QUEUE_CAP=0` | Pendiente | — |
| RF-17 | Ayuda de uso y códigos de salida del cliente | Alta | Prueba/Inspección | TC-015 | salida de `help` + códigos | Pendiente | — |
| RF-18 | Operación remota con protocolo documentado | Alta | Prueba/Demo | TC-010 | cliente y servidor | Pendiente | — |
| RF-19 | Misma semántica local y remota | Alta | Prueba/Demo | TC-010 | cliente y servidor | Pendiente | — |
| RF-20 | Solo LAN/VPN autorizada | Crítica | Prueba/Análisis | TC-011 | configuración + intento | Pendiente | — |
| RF-21 | Protocolo delimitado, tolera lecturas/escrituras parciales | Alta | Prueba | TC-012 | resultado + log | Pendiente | — |
| RF-22 | Desconexión de cliente sin afectar servicio ni trabajos | Alta | Prueba | TC-012, TC-019 | resultado + log | Pendiente | — |
| RF-23 | Rechazar y registrar solicitudes que excedan límites | Crítica | Prueba | TC-016 | rejection.txt + daemon.log | PASS | N/A |
| RF-24 | Resumen de salud: activo, en ejecución, en cola, errores | Alta | Prueba | TC-013 | salida de `health` | Pendiente | — |
| RF-25 | Rechazo explícito con cola llena, sin bloquear ni perder trabajos | Crítica | Prueba | TC-016 | rejection.txt + status antes/después | PASS | N/A |
| RF-26 | Cancelaciones concurrentes con estado final coherente | Crítica | Prueba | TC-017 | respuestas + estado final | PASS | N/A |
| RF-27 | Solicitud duplicada sin estados contradictorios | Crítica | Prueba | TC-018 | respuestas + status | PASS | N/A |
| RF-28 | Desconexión durante solicitud con estado coherente | Crítica | Prueba | TC-019 | respuestas + status + log | Pendiente | — |
| RF-29 | Terminación inesperada del hijo: detectar, liberar y registrar | Crítica | Prueba | TC-020 | estados + ps + log | Pendiente | Esperando a Uriel |
| RF-30 | Escalamiento de cancelación documentado y verificable | Crítica | Prueba | TC-021 | señales + estados + log | Pendiente | — |

## Requisitos no funcionales

| Req ID | Descripción breve | Prioridad | Método | Caso(s) | Evidencia | Resultado | Defecto/Excepción |
|:-------|:------------------|:---------:|:------:|:--------|:----------|:---------:|:------------------|
| RNF-01 | Compilar y ejecutar en Linux declarado | Alta | Prueba | TC-014 | resultado + log | Pendiente | falta diseñar el script |
| RNF-02 | Construcción reproducible desde clon limpio | Alta | Prueba/Inspección | TC-014 | log de build | Pendiente | falta diseñar el script |
| RNF-03 | Sin privilegios de root | Alta | Prueba | TC-014 | `id -u` + log | Pendiente | falta diseñar el script |
| RNF-04 | Con límite 3, al menos 3 trabajos simultáneos | Alta | Prueba | TC-002 | ps-samples + resumen | PASS | N/A |
| RNF-05 | Consulta de estado ≤ 1 s con 100 trabajos | Alta | Prueba | TC-004 | tiempos medidos | PASS | N/A |
| RNF-06 | Soportar al menos 500 registros sin pérdida | Alta | Prueba | TC-007 | conteo antes/después de reiniciar | PASS | N/A |
| RNF-07 | La cola no inicia más procesos que el límite | Alta | Prueba | TC-002 | ps-samples + resumen | PASS | N/A |
| RNF-08 | Solicitud inválida o desconexión no termina el servicio | Alta | Prueba | TC-008 | resultado + log | Pendiente | — |
| RNF-09 | Terminación anormal de un trabajo no afecta a otros | Crítica | Prueba | TC-008 | log + estados | Pendiente | — |
| RNF-10 | Tras reiniciar, no reportar RUNNING un proceso no controlado | Alta | Prueba | TC-007 | resultado + log | PASS | N/A |
| RNF-11 | Escritura de archivos persistentes sin estado parcial | Alta | Prueba | TC-007, TC-022 | resultado + log | BLOCKED | FALTA VERIFICAR TC-022 |
| RNF-12 | No escuchar en interfaces públicas por defecto | Crítica | Prueba/Inspección | TC-011 | `ss -ltn` + configuración | Pendiente | — |
| RNF-13 | Acceso remoto limitado a localhost, subred privada o VPN | Crítica | Prueba | TC-011 | configuración + intento | Pendiente | — |
| RNF-14 | Validar longitud y formato de mensajes de red | Alta | Prueba | TC-012 | resultado + log | Pendiente | — |
| RNF-15 | Registros sin secretos | Alta | Inspección | revisión de `daemon.log` y código (propuesto) | grep + revisión | Pendiente | — |
| RNF-16 | Mínimo privilegio y modelo de amenazas básico | Alta | Inspección | documento de amenazas (propuesto) | documento | Pendiente | — |
| RNF-17 | Módulos con responsabilidades identificables | Alta | Inspección | revisión de `src/` | estructura del repositorio | PASS | N/A |
| RNF-18 | Interfaces públicas y decisiones documentadas | Alta | Inspección | ADR + guías | documentos | PASS | N/A |
| RNF-19 | Compilar sin advertencias nuevas | Alta | Prueba | TC-014 (propuesto) | log de `cargo build` y `clippy` en CI | Pendiente | — |
| RNF-20 | Pruebas con un único comando documentado | Alta | Prueba | TC-014 (propuesto) | ejecución de `run-all.sh` | Pendiente | — |
| RNF-21 | Errores con operación, causa y acción sugerida | Alta | Prueba | TC-015, TC-016 | mensajes capturados | BLOCKED | Falta TC-015 |
| RNF-22 | Bitácora que correlaciona solicitud con trabajo | Alta | Prueba | TC-020 (propuesto) | daemon.log | Pendiente | — |
| RNF-23 | Guía de usuario suficiente sin asistencia | Alta | Prueba/Demo | TC-015 | prueba con un usuario ajeno | Pendiente | — |
| RNF-24 | Protocolo con mensajes fragmentados y solicitudes secuenciales | Alta | Prueba | TC-012 | resultado + log | Pendiente | — |
| RNF-25 | Liberar sockets y procesos hijos al cerrar | Alta | Prueba | TC-009 | ps + ss + log | Pendiente | — |
| RNF-26 | Demostración solo en red privada o VPN | Crítica | Inspección/Demo | TC-010, TC-011 | bind + reglas | Pendiente | — |
| RNF-27 | Transiciones consistentes ante concurrencia, sin regresiones | Crítica | Prueba | TC-017 | estados + log | PASS | — |
| RNF-28 | Actualizaciones persistentes atómicas o recuperables | Crítica | Prueba | TC-022 | archivos antes/después + log | Pendiente | — |
| RNF-29 | Backpressure o rechazo explícito en límites | Crítica | Prueba | TC-016 | rejection.txt + recovery.txt | PASS | — |
| RNF-30 | Sin procesos huérfanos tras cierre o falla | Crítica | Prueba | TC-020, TC-009 | ps + log | Pendiente | — |
| RNF-31 | Recuperación distingue pendientes, terminados e interrumpidos | Crítica | Prueba | TC-007, TC-022 | estados antes/después | BLOCKED | Falta 022 |
| RNF-32 | Compatibilidad de versión del protocolo | Alta | Prueba | TC-023 | respuesta a versión incompatible | Pendiente | — |
| RNF-33 | Liberación de memoria, procesos, archivos y sockets bajo estrés | Alta | Prueba | TC-024 | fds + procesos + memoria | Pendiente | — |
| RNF-34 | Decisiones de seguridad/consistencia con análisis de riesgo y prueba | Alta | Inspección | ADR + registro de riesgos (propuesto) | documentos | Pendiente | — |

>>>>>>> Stashed changes
## Cobertura por caso

| Caso | Título | Requisitos | Script | Estado |
|:-----|:-------|:-----------|:-------|:-------|
| TC-001 | Enviar trabajo válido | RF-01, RF-02, RF-04 | `TC-001.sh` | PASS |
| TC-002 | Cola y límite de concurrencia | RF-03, RF-05, RNF-04, RNF-07 | `TC-002.sh` | PASS |
| TC-003 | Estados y tiempos | RF-06, RF-07 | `TC-003.sh` | PASS |
| TC-004 | Consultar y listar | RF-08, RF-09, RNF-05 | `TC-004.sh` | PASS |
| TC-005 | Cancelar en cola y ejecución | RF-10, RNF-21, RNF-30 | `TC-005.sh` | PASS |
| TC-006 | Capturar stdout/stderr y código | RF-11, RF-07 | `TC-006.sh` | PASS |
| TC-007 | Reinicio y recuperación | RF-12, RF-13, RNF-06, RNF-10, RNF-11, RNF-31 | `TC-007.sh` | PASS |
| TC-008 | Aislamiento de fallo | RNF-08, RNF-09 | — | Sin redactar |
| TC-009 | Cierre controlado | RF-15, RNF-25, RNF-30 | — | Sin redactar |
| TC-016 | Saturación de cola y rechazo explícito | RF-23, RF-25, RNF-21, RNF-29 | `TC-016.sh` | PASS |
| TC-017 | Cancelaciones concurrentes | RF-26, RNF-27 | `TC-017.sh` | PASS |
| TC-018 | Solicitud duplicada | RF-27, RNF-27 | `TC-018.sh` | PASS |
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
