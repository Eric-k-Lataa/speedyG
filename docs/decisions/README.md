# Registro de decisiones de arquitectura (ADR)

Este directorio contiene las decisiones de arquitectura de speedyG.
Cada ADR documenta el contexto, las alternativas consideradas, la decisión
seleccionada, sus consecuencias y los requisitos afectados.

## Índice de decisiones

| ADR | Decisión | Estado | Fecha | Requisitos afectados |
|---|---|---|---|---|
| [ADR-01: Lenguaje de programación](ADR-01-Lenguaje.md) | Selección de Rust como lenguaje de implementación. | Aceptado | 11-09-2026 | RF-01, RF-02, RF-05, RNF-01, RNF-04, RNF-08, RNF-09, RNF-10, RNF-30, RNF-33 |
| [ADR-02: Selección de la Arquitectura](ADR-02-Arquitectura.md) | Arquitectura basada en Event Loop y FSM. | Aceptado | 11-09-2026 | RF-01, RF-04, RF-05, RF-07, RNF-01, RNF-02, RNF-04 |
| [ADR-03: Mecanismo de persistencia](ADR-03-persistence.md) | SQLite como persistencia principal y JSON como respaldo. | Aceptado | 11-09-2026 | RF-08, RF-09, RF-12, RF-13, RNF-05, RNF-06, RNF-11, RNF-28, RNF-31 |
| [ADR-04: Cancelación, escalamiento, duplicados y saturación](ADR-04-Cancelacion,escalamiento,duplicados,saturacion.md) | Política de cancelación, escalamiento de señales, solicitudes duplicadas independientes y límite de cola. | Aceptado | 27-10-2026 | RF-25, RF-23, RNF-29, RF-27, RF-10, RF-30, RNF-30, RF-26, RNF-27, RF-12, RF-13, RNF-06 |
| [ADR-05: Modelo de Concurrencia, Estado Compartido y Gestión de Procesos Hijos](ADR-05-Concurrencia.md) | `std::sync::Mutex` para el estado compartido y `tokio::process` con grupos de procesos para ejecutar y controlar trabajos. | Aceptado | 30-10-2026 | RF-03, RF-05, RNF-07, RNF-27, RNF-34, RF-04, RF-10, RF-26, RNF-30 |
| [ADR-06: Protocolo de Red](ADR-06-ProtocoloRed.md) | Definición del protocolo de comunicación mediante sockets Unix y TCP. | Aceptado | 24-11-2026 | RF-19, RNF-29, RNF-32, RNF-34 |
| [ADR-07: Política de retención de resultados y límites de recursos](ADR-07-RetencionResultados,LimiteRecursos.md) | Límites de salida por trabajo y retención máxima de trabajos terminados. | Aceptado | 26-11-2026 | RF-11, RF-12, RF-13, RF-23, RNF-06, RNF-29 |

## Estados

- **Propuesto:** decisión pendiente de aprobación.
- **Aceptado:** decisión aprobada y vigente.
- **Reemplazado:** decisión sustituida por otra posterior.

## Notas

- Las fechas corresponden a la fecha de cada decisión, no a la fecha de actualización del índice
- Los requisitos afectados se identifican en la sección correspondiente de cada ADR
- Cuando un dato aparece como pendiente de verificar, debe confirmarse en el documento original antes de completar el índice
