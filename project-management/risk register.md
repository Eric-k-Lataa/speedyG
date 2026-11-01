# Registro de Riesgos - Avance 02

## Objetivo

Identificar, evaluar y monitorear los riesgos técnicos y de gestión asociados al desarrollo de speedyG, incluyendo concurrencia, cancelación, persistencia, recuperación, verificación y coordinación de actividades del equipo.

---

### Probabilidad

| Valor | Significado |
|---------|---------|
| Baja | Poco probable |
| Media | Posible |
| Alta | Probable |

### Impacto

| Valor | Significado |
|---------|---------|
| Bajo | Afecta parcialmente una funcionalidad |
| Medio | Afecta múltiples funcionalidades |
| Alto | Compromete requisitos importantes |
| Crítico | Compromete la estabilidad o aceptación del proyecto |

---

## Registro de riesgos

| R-01 | Transiciones inválidas entre estados generan inconsistencias en los trabajos | Baja | Crítico | FSM validada mediante pruebas unitarias y revisión del modelo de estados | Carolina | Mitigado | A2-01 |
| R-02 | Divergencia entre el estado de la FSM y el estado real del proceso en el sistema operativo | Media | Crítico | Recolección obligatoria mediante wait() antes de transiciones finales | Uriel | Mitigado | ADR-05, TC-005 |
| R-03 | Cancelaciones concurrentes generan estados inconsistentes | Media | Crítico | Serialización de cancelaciones y validación | Paola | Mitigado | TC-017 |
| R-04 | Comandos mal formados son aceptados incorrectamente | Media | Medio | Mantener validaciones de entrada y pruebas de rechazo | Carolina | Mitigado | TC-001 |
| R-05 | Corrupción o pérdida de información persistida durante una escritura | Media | Alto | Persistencia controlada y pruebas de recuperación del Scheduler | Paola | En seguimiento | ADR-03 |
| R-06 | Recuperación incorrecta de trabajos después de reiniciar el servicio | Media | Alto | Verificación de recuperación de estados persistidos | Paola | En seguimiento | ADR-03 |
| R-07 | Casos de prueba insuficientes para detectar regresiones | Media | Alto | Mantener trazabilidad entre requisitos, TC y evidencia | Erick | Mitigado | A2-15, A2-24 |
| R-08 | Procesos que invocan setsid() escapan al grupo de procesos y no reciben señales | Baja | Medio | Documentar como limitación conocida del sistema | Uriel | En seguimiento | ADR-05 |
| R-09 | Generación de evidencia insuficiente para demostrar cumplimiento de requisitos | Media | Crítico | Mantener casos de prueba reproducibles y evidencia verificable | Erick | Mitigado | A2-23 |
| R-10 | ADR, arquitectura y código quedan desalineados | Media | Medio | Revisiones cruzadas antes de merge | Equipo | En seguimiento | A2-02, A2-04, A2-29 |
| R-11 | Dependencias entre issues provocan bloqueos en tareas posteriores | Media | Medio | Mantener cronograma y seguimiento de dependencias | Equipo | En seguimiento | A2-30 |

---

## Resumen

| Estado | Cantidad |
|---------|---------|
| Mitigado | 6 |
| En seguimiento | 5 |

---
