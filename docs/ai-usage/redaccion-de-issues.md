# Registro de uso de IA: Asistencia en Redacción de Issues de Requerimientos

## Objetivo

Obtener asistencia para estructurar y redactar issues técnicos y de requerimientos en GitHub para el Avance 2 de speedyG, asegurando claridad, criterios de aceptación verificables y trazabilidad con los requisitos del sistema.

## Pregunta realizada a la IA

> "Ayúdame a redactar un issue en GitHub para la tarea de gestión del log de uso de IA (AI-LOG) del Avance 2 de speedyG. Necesito que describa el contexto, qué se debe documentar, cómo debe validarse y qué evidencia se requiere para cerrarlo."

## Resultado recibido

```markdown
### [Feature] Registro de uso de Inteligencia Artificial

**Como** desarrollador del equipo de speedyG,  
**Quiero** documentar cómo y cuándo usamos herramientas de IA en el proyecto,  
**Para** cumplir con los lineamientos de transparencia y evaluar su impacto.

#### Descripción
Debemos registrar en la carpeta `docs/ai-usage/` los casos donde usamos IA.

#### Criterios de Aceptación
- [ ] Subir archivos a `docs/ai-usage/`
- [ ] Explicar qué prompt se usó
- [ ] Decir si sirvió o no
- [ ] Que todos los miembros hayan subido al menos una entrada

#### Tareas
- Crear los archivos markdown
- Hacer commit y push
```

## Revisión realizada

Se analizó la propuesta generada por la IA y se comparó con el estándar formal de gestión de proyectos e ingeniería de software de speedyG:

1. **Deficiencia de formato**: La IA utilizó un formato genérico de historia de usuario (*User Story* tipo Scrum: "Como... Quiero... Para..."), el cual no se alinea con la nomenclatura estándar del repositorio (`[REQ] A2-XX — NOMBRE` o `[TASK]`).
2. **Falta de rigor en criterios de aceptación**: Los criterios sugeridos eran vagos ("Decir si sirvió o no") y no contemplaban las categorías requeridas por la rúbrica del proyecto (objetivo, prompt, resultado recibido, revisión crítica, cambios, prueba agregada, aprendizaje y clasificación formal: aceptado / modificado / rechazado).
3. **Ausencia de metadatos del proyecto**: No incluía trazabilidad a Requisitos Funcionales/No Funcionales (RF/RNF), asignación de responsable, prioridad técnica, dependencias bloqueantes ni evidencia reproducible de cierre.

## Decisión

**Modificado**

Se descartó el formato genérico de historia de usuario y se reescribió el issue adaptándolo al estándar formal de speedyG. Se conservó la idea de desglosar el objetivo y contexto, pero se especificaron con precisión los criterios técnicos de evaluación y la estructura obligatoria de cada registro en `docs/ai-usage/`.

## Cambios realizados

1. Se cambió el título al formato oficial del proyecto: `[REQ] A2-28 — AI-LOG (#82)`.
2. Se definieron criterios de aceptación medibles:
   - Registro con secciones obligatorias: objetivo, resultado, revisión, cambios, prueba agregada y aprendizaje.
   - Presencia de al menos un resultado aceptado tras verificación, uno modificado por deficiencia y uno rechazado con motivo técnico.
   - Capacidad de cada integrante de explicar sus entradas.
3. Se agregaron los campos de metadatos: *RF/RNF relacionados*, *Responsable*, *Prioridad*, *Dependencias* y *Evidencia de cierre*.

## Prueba agregada / Verificación

- Se publicó el issue [#82] en GitHub Issues siguiendo la estructura final modificada.
- Se verificó que el equipo de desarrollo pudiera comprender el alcance sin ambigüedades y que los criterios de aceptación sirvieran como lista de verificación directa para el cierre del requerimiento.

## Aprendizaje

Las herramientas de IA frecuentemente generan plantillas genéricas de desarrollo ágil que resultan insuficientes para proyectos con requerimientos estrictos de ingeniería, trazabilidad y verificación formal. La asistencia de la IA es útil para disparar ideas de redacción iniciales, pero es indispensable una revisión y adaptación crítica para ajustarse a los estándares de documentación del proyecto.
