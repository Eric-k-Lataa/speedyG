# Registro de uso de IA

## Objetivo

Obtener una propuesta de estructura y contenido para elaborar el **Plan de Verificación de speedyG**, tomando como base los requisitos del proyecto y el proceso de verificación establecido para el Avance 1.

## Pregunta realizada a la IA

> "Ayúdame a estructurar y mejorar un plan de verificación para el proyecto speedyG. Debe incluir el alcance del Avance 1, requisitos que se verificarán, métodos de verificación (PRUEBA, ANÁLISIS, INSPECCIÓN y DEMOSTRACIÓN), niveles de verificación, criterios de entrada y salida, ambiente controlado, evidencias esperadas, manejo de PASS/FAIL/BLOCKED y la relación entre requisito, caso de prueba y evidencia."

## Resultado recibido

La IA propuso una estructura para el Plan de Verificación que incluye los siguientes apartados:

* Alcance de Avance 1.
* Requisitos que se verificarán.
* Métodos de verificación.
* Niveles de verificación.
* Criterios de entrada.
* Criterios de salida.
* Ambiente controlado.
* Evidencias esperadas.
* Manejo de PASS / FAIL / BLOCKED.
* Relación requisito → caso → evidencia.

También se propuso describir dentro de cada sección los criterios y procedimientos necesarios para realizar una verificación reproducible del sistema.

## Revisión realizada

Se revisó la propuesta de la IA y se comparó con los requisitos y estructura de verificación definidos para el proyecto.

Se verificó que los apartados propuestos fueran compatibles con la documentación de speedyG y con la estructura del repositorio:

`verif/verification-plan/`

`verif/test-cases/`

`verif/scripts/`

`verif/test-data/`

`verif/results/`

También se revisó que el plan distinguiera entre las funcionalidades que pueden verificarse durante el Avance 1 y aquellas que todavía dependen de funcionalidades no implementadas.

Se consideró especialmente el uso del estado **BLOCKED**, para evitar marcar como FAIL requisitos que todavía no pueden ser ejecutados debido a funcionalidades pendientes de implementación.

## Decisión

**Modificado**

La estructura propuesta por la IA se utilizó como base para elaborar el Plan de Verificación de speedyG.

El contenido fue adaptado al proyecto y se agregaron detalles específicos sobre:

* El alcance del Avance 1.
* Los requisitos funcionales y no funcionales del proyecto.
* Los niveles Unit, Integration, System, Robustness, Security y Acceptance.
* Los criterios de entrada y salida de las verificaciones.
* La información que debe registrarse del ambiente controlado.
* Los tipos de evidencia aceptados.
* Las condiciones para determinar PASS, FAIL o BLOCKED.
* La relación entre requisitos, casos de prueba y evidencias mediante la matriz de trazabilidad.
* El manejo de defectos y la repetición de pruebas después de una corrección.

La propuesta de la IA no se incorporó directamente sin revisión; fue utilizada como apoyo para organizar y redactar el documento.

## Prueba agregada

Se revisó la estructura del Plan de Verificación para comprobar que los requisitos necesarios para el proceso de verificación estuvieran contemplados y que existiera una relación clara entre:

**Requisito → Método → Caso de prueba → Evidencia → Resultado**

También se comprobó que el plan permitiera registrar casos que todavía no pueden ejecutarse mediante el estado **BLOCKED**, diferenciándolos de los casos que realmente presentan un incumplimiento.

## Aprendizaje

Se comprendió mejor cómo estructurar un Plan de Verificación y cómo relacionarlo con los casos de prueba y la matriz de trazabilidad.

También se reforzó la importancia de definir previamente los criterios de entrada, salida y evidencia, en lugar de limitar la verificación a ejecutar pruebas y determinar si funcionan o no.

El uso de la IA facilitó la organización inicial del documento, pero fue necesario revisar y adaptar la propuesta para que correspondiera con los requisitos, alcance y estado actual del proyecto speedyG.
