
# Registro de Uso de Inteligencia Artificial (AI-LOG) — speedyG

Este directorio documenta de manera transparente, crítica y sistemática el uso de herramientas de Inteligencia Artificial durante las diferentes etapas de desarrollo, diseño, verificación y gestión del proyecto **speedyG**.

---

## Criterios de Documentación

Cada entrada en esta carpeta cumple con la siguiente estructura:
1. **Objetivo**: Qué se buscaba resolver o consultar con la IA.
2. **Pregunta / Prompt**: Consulta exacta realizada al modelo de IA.
3. **Resultado recibido**: Respuesta original o propuesta entregada por la IA.
4. **Revisión crítica**: Análisis técnico de la respuesta frente a los requisitos, restricciones y arquitectura de speedyG.
5. **Decisión**: Clasificación explícita de la propuesta:
   - **Aceptado tras verificación**: Se validó técnica o empíricamente y se adoptó tal como fue propuesta.
   - **Modificado**: Se requirieron adaptaciones o correcciones para ajustarse a los estándares o requerimientos del proyecto.
   - **Rechazado**: Se descartó la propuesta debido a deficiencias técnicas, arquitectónicas o de alcance.
6. **Cambios realizados**: Ajustes específicos aplicados en base a la revisión.
7. **Prueba agregada / Verificación**: Mecanismo de prueba, script, test o validación realizada para comprobar la efectividad.
8. **Aprendizaje**: Conclusiones técnicas y metodológicas sobre el uso de la herramienta.

---

## Catálogo de Registros

### Avance 1
| Registro | Título / Tema | Decisión | Resumen |
| :--- | :--- | :---: | :--- |
| [`ejemplo-01-fsm.md`](./ejemplo-01-fsm.md) | Implementación inicial de Máquina de Estados (FSM) en Rust | **Modificado** | Se tomó la idea básica de enums/match en Rust, pero se adaptaron los estados reales, warnings y getters de speedyG. |
| [`ejemplo-02-parser.md`](./ejemplo-02-parser.md) | Estructura para el Parser de Comandos | **Rechazado** | Propuesta no genérica que acoplaba reconocimiento con validación; se rediseñó para separar responsabilidades. |
| [`estructurar-plan-de-verificacion.md`](./estructurar-plan-de-verificacion.md) | Estructura del Plan de Verificación | **Modificado** | Estructura general adaptada para incorporar niveles de prueba, ambiente controlado, matriz de trazabilidad y estado `BLOCKED`. |

### Avance 2
| Registro | Título / Tema | Decisión | Resumen |
| :--- | :--- | :---: | :--- |
| [`redaccion-de-issues.md`](./redaccion-de-issues.md) | Asistencia en Redacción de Issues de Requerimientos en GitHub | **Modificado** | Se modificó la plantilla genérica de User Story por el formato formal de speedyG con metadatos de trazabilidad y criterios medibles. |
| [`redaccion-pull-requests.md`](./redaccion-pull-requests.md) | Asistencia en Redacción de Descripciones para Pull Requests | **Aceptado tras verificación** | Se aceptó la plantilla de PR estructurada con checklist de sanidad, trazabilidad a issues y comandos de prueba locales. |

---

## Balance de Decisiones Técnicas

El conjunto de registros de uso de IA satisface el balance crítico exigido por el estándar de ingeniería:
- **Aceptado tras verificación**: [`redaccion-pull-requests.md`](./redaccion-pull-requests.md)
- **Modificado por deficiencia / adaptación**: [`ejemplo-01-fsm.md`](./ejemplo-01-fsm.md), [`estructurar-plan-de-verificacion.md`](./estructurar-plan-de-verificacion.md), [`redaccion-de-issues.md`](./redaccion-de-issues.md)
- **Rechazado por motivo técnico**: [`ejemplo-02-parser.md`](./ejemplo-02-parser.md)