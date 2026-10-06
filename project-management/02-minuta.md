# Minuta de Reunión

## Información General

**Fecha:** 2026-10-03

**Hora de inicio:** 16:00

**Hora de finalización:** 20:00

**Lugar / Medio:**
Virtual a través de Google Meet

**Moderador:**
Diego Binervia

**Responsable de la minuta:**
Erick Padilla

---

# Asistentes

| Integrante | Asistió |
| ---------- | ------- |
| Erick      | ✅       |
| Carolina   | ✅       |
| Paola      | ✅       |
| Uriel      | ✅       |

---

# Objetivo de la reunión

> Revisar y consolidar el avance realizado por los cuatro integrantes del equipo de cara al primer Review, identificar defectos y pendientes, definir los próximos casos de prueba y distribuir las actividades restantes de manera equilibrada. Asimismo, se busca establecer un cronograma con fechas claras, acordar posibles mejoras al proyecto y asegurar la trazabilidad entre las actividades, Issues y Pull Requests correspondientes, de manera que el equipo llegue preparado y organizado a la revisión con el profesor.

---

# Temas discutidos

## Revisión del avance individual

### Discusión

**Uriel**

Uriel inicia la reunión y realiza una grabación como evidencia de la sesión. Se realiza un recorrido completo desde el clon del repositorio hasta la instalación y ejecución del proyecto.

Se explica el funcionamiento de **Tokio**, particularmente su papel como biblioteca de runtime asíncrono que permite gestionar operaciones concurrentes e interacción con recursos del sistema operativo.

Se revisa el flujo general de ejecución de un trabajo y se realizan preguntas sobre la arquitectura y el funcionamiento interno del sistema.

**Paola**

Paola continúa con una explicación del funcionamiento del `scheduler.rs` y responde preguntas relacionadas con la administración de los trabajos y su estado.

También se realiza una ronda de preguntas para comprobar que los integrantes comprendan las decisiones de implementación y puedan defenderlas durante el Review.

**Carolina**

Carolina explica el funcionamiento del parser y de la máquina de estados.

Se revisa el comportamiento de los comandos disponibles y el manejo de estados de los trabajos. Se comenta que actualmente ya es posible solicitar la cancelación de trabajos durante su ejecución, quedando pendiente verificar mediante pruebas que el comportamiento sea correcto.

### Acuerdos

* Cada integrante deberá ser capaz de explicar su parte del proyecto y responder preguntas relacionadas con su implementación.
* Se utilizará la grabación de la reunión como apoyo para revisar posteriormente las explicaciones y detectar temas que requieran mayor preparación.
* Todos los integrantes deberán conocer, al menos a nivel general, el flujo completo del sistema para evitar depender exclusivamente de la persona que implementó cada componente.

---

## Estado actual del proyecto

### Discusión

Se revisa el estado de los componentes principales del proyecto y las funcionalidades implementadas hasta el momento.

Paola comenta que ha trabajado principalmente en la persistencia mediante JSON. Esta implementación todavía no se integrará al commit previsto antes del viernes, pero se considera útil para contar con una implementación funcional que pueda utilizarse como apoyo durante la presentación.

Se comenta la necesidad de evitar sobrescrituras o inconsistencias en la persistencia y se plantea revisar posteriormente una alternativa basada en SQL/almacenamiento persistente.

También se identifica la necesidad de verificar mediante pruebas el comportamiento de funcionalidades que ya fueron implementadas pero que todavía no cuentan con evidencia suficiente.

### Acuerdos

* La implementación de persistencia mediante JSON se mantendrá como trabajo en desarrollo y se evaluará su integración posteriormente.
* No se considerará una funcionalidad como completamente validada hasta contar con un caso de prueba y evidencia correspondiente.
* Se continuará revisando la implementación antes de incorporar cambios que puedan afectar la estabilidad del proyecto.

---

## Planificación de Casos de Prueba

### Discusión

Se revisan los casos de prueba que deben desarrollarse para cubrir los requisitos funcionales y no funcionales pendientes.

Se identifica como prioridad continuar con los casos relacionados con la consulta, listado y cancelación de trabajos.

Se propone trabajar en:

* **TC-004 — Consultar y listar trabajos**, relacionado con RF-08, RF-09 y RNF-05.
* **TC-005 — Cancelar trabajo**, relacionado con RF-10.

Se acuerda prestar especial atención al comportamiento de la cancelación de trabajos tanto cuando se encuentran en cola como cuando ya están en ejecución.

También se identifica que las pruebas deberán generar evidencia reproducible y mantenerse vinculadas con los requisitos correspondientes mediante la matriz de trazabilidad.

### Acuerdos

* Desarrollar **TC-004 — Consultar y listar trabajos**.
* Desarrollar **TC-005 — Cancelar trabajo en cola y ejecución**.
* Verificar específicamente que la cancelación de un trabajo en ejecución produzca el comportamiento esperado.
* Mantener la trazabilidad entre requisitos, casos de prueba, scripts y evidencia.
* Todo FAIL detectado durante las pruebas deberá generar el Issue correspondiente de acuerdo con el proceso de gestión de defectos.

---

## Distribución de actividades para el Review 1

### Discusión

Se revisa la distribución de responsabilidades para la presentación del Review.

Se plantea que:

* **Diego** apoyará con la coordinación y presentación general.
* **Erick** se encargará principalmente de explicar las pruebas, verificación y evidencia.
* **Carolina** explicará principalmente la máquina de estados y el parser.
* **Paola** explicará principalmente el scheduler y los componentes relacionados con la persistencia.

Se comenta que no basta con que cada integrante conozca únicamente su parte. Todos deberán estar preparados para responder preguntas generales sobre la arquitectura y el funcionamiento del sistema.

Se plantea que durante la presentación se debe intentar "vender la idea" del proyecto, mostrando claramente qué problema resuelve, cómo funciona y por qué las decisiones técnicas tomadas son adecuadas.

También se considera importante que los integrantes estén alineados respecto a las respuestas que proporcionarán ante preguntas del profesor.

### Acuerdos

* Cada integrante preparará la explicación de su componente principal.
* Todos deberán conocer el flujo general del sistema.
* Se realizará preparación conjunta para anticipar preguntas del Review.
* La presentación deberá enfocarse no solo en mostrar código, sino en explicar las decisiones técnicas y justificar la arquitectura.

---

## Propuestas de mejora

### Discusión

Durante la revisión se identifican oportunidades para mejorar la preparación del proyecto antes del Review.

Entre ellas:

* Mejorar la evidencia de las pruebas.
* Completar los casos de prueba pendientes.
* Mantener actualizada la matriz de trazabilidad.
* Registrar formalmente los defectos encontrados durante las pruebas.
* Relacionar Issues, Pull Requests, casos de prueba y requisitos.
* Preparar respuestas para posibles preguntas técnicas sobre Tokio, procesos, señales, scheduler, máquina de estados y ejecución asíncrona.
* Verificar funcionalidades que ya fueron implementadas pero que todavía no cuentan con evidencia suficiente.

### Acuerdos

* Priorizar las actividades que tengan impacto directo en la preparación para el Review.
* Mantener actualizada la documentación conforme se realicen cambios.
* No dejar funcionalidades implementadas sin una estrategia de verificación asociada.

---

## Actualización del cronograma

### Discusión

Se revisan las actividades restantes para llegar preparados al primer Review.

Se establece como prioridad terminar los casos de prueba pendientes y validar las funcionalidades principales del sistema antes de la presentación.

También se considera necesario reservar tiempo para ejecutar nuevamente las pruebas después de las correcciones y documentar los resultados.

### Acuerdos

* Priorizar TC-004 y TC-005.
* Ejecutar las pruebas después de cada corrección relevante.
* Documentar los resultados y evidencias antes del Review.
* Realizar una preparación final de la presentación y preguntas técnicas.

---

## Trazabilidad entre Issues y Pull Requests

### Discusión

Se acuerda mantener una relación clara entre los problemas encontrados, las correcciones y los cambios realizados en el repositorio.

Se revisa la importancia de que los defectos detectados durante las pruebas sean registrados como Issues y posteriormente relacionados con los Pull Requests que implementen su corrección.

Se establece como flujo:

**FAIL → Issue → Corrección → Pull Request → Prueba de regresión → Cierre del Issue.**

También se comenta que GitHub Actions permitirá ejecutar automáticamente las pruebas asociadas al proyecto y proporcionar evidencia adicional de las correcciones.

### Acuerdos

* Todo FAIL deberá generar un Issue de acuerdo con el proceso de gestión de defectos.
* Los Pull Requests deberán relacionarse con los Issues correspondientes.
* Después de una corrección se deberá repetir el caso de prueba afectado y las regresiones correspondientes.
* GitHub Actions será utilizado como apoyo para la ejecución automática de las pruebas.
* Mantener actualizada la trazabilidad entre requisitos, casos de prueba, Issues, Pull Requests y evidencia.

---

## Acuerdos y próximos pasos

### Discusión

Se identifican como siguientes actividades principales:

1. Verificar que la cancelación de trabajos funcione correctamente cuando el trabajo se encuentra **en cola**.
2. Verificar el comportamiento de la cancelación cuando el trabajo se encuentra **en ejecución**.
3. Implementar y ejecutar **TC-005**, relacionado con RF-10.
4. Implementar **TC-004**, relacionado con RF-08, RF-09 y RNF-05.
5. Verificar que el sistema permita consultar la información necesaria de un trabajo mediante su ID.
6. Verificar el listado de trabajos y los filtros por estado requeridos.
7. Verificar el tiempo de respuesta de las consultas con 100 trabajos almacenados.
8. Continuar con la preparación para el Review y realizar una sesión de preguntas entre los integrantes.

### Acuerdos

* **Erick:** continuar con la elaboración y automatización de los casos de prueba pendientes y mantener actualizada la evidencia de verificación.
* **Carolina:** continuar con la preparación y explicación del parser y la máquina de estados.
* **Paola:** continuar con el scheduler y los trabajos relacionados con persistencia.
* **Uriel:** apoyar con la revisión de la ejecución general y la preparación para la demostración.
* Todos los integrantes deberán revisar el funcionamiento general del proyecto antes del Review.

---

# Decisiones Tomadas

| ID    | Decisión                                                                                                                     | Estado   |
| ----- | ---------------------------------------------------------------------------------------------------------------------------- | -------- |
| D-001 | Utilizaremos el lenguaje de Rust para el proyecto                                                                            | Aprobada |
| D-002 | Se utilizará una arquitectura de Bucle de Eventos con Máquina de Estados Finitos (Event Loop + FSM)                          | Aprobada |
| D-003 | Se asignaron todas las tareas para el avance 00                                                                              | Aprobada |
| D-004 | Se continuará la verificación mediante casos de prueba trazables a los requisitos                                            | Aprobada |
| D-005 | Todo FAIL deberá generar un Issue con su evidencia correspondiente                                                           | Aprobada |
| D-006 | Después de una corrección se repetirá el caso afectado y las regresiones correspondientes                                    | Aprobada |
| D-007 | Se priorizarán TC-004 y TC-005 como siguientes casos de prueba                                                               | Aprobada |
| D-008 | Se utilizará GitHub Actions para apoyar la ejecución automatizada de las pruebas                                             | Aprobada |
| D-009 | Los Issues y Pull Requests deberán mantenerse relacionados para conservar la trazabilidad de los defectos y sus correcciones | Aprobada |

---

# Pendientes

| ID    | Actividad                                                       | Responsable | Estado    |
| ----- | --------------------------------------------------------------- | ----------- | --------- |
| P-001 | Implementar TC-004 — Consultar y listar trabajos                | Erick       | Pendiente |
| P-002 | Implementar TC-005 — Cancelar trabajo en cola y ejecución       | Erick       | Pendiente |
| P-003 | Verificar el comportamiento de cancelación durante la ejecución | Equipo      | Pendiente |
| P-004 | Verificar consulta y metadatos de trabajos mediante ID          | Equipo      | Pendiente |
| P-005 | Verificar filtros de listado por estado                         | Equipo      | Pendiente |
| P-006 | Verificar RNF-05 con 100 trabajos almacenados                   | Erick       | Pendiente |
| P-007 | Mantener actualizada la matriz de trazabilidad                  | Erick       | Pendiente |
| P-008 | Preparar preguntas y respuestas para el Review                  | Equipo      | Pendiente |
| P-009 | Revisar e integrar los cambios pendientes de persistencia       | Paola       | Pendiente |
| P-010 | Ejecutar regresiones después de las correcciones                | Erick       | Pendiente |
