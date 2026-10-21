# Plan de verificación para speedyG

## 1. Alcance de Avance 1

El objetivo de este plan es establecer el proceso para verificar de manera reproducible el funcionamiento y la calidad del proyecto **speedyG**, así como mantener la trazabilidad entre los requisitos, los casos de prueba y las evidencias obtenidas durante su ejecución.

Para el **Avance 1** se verificará principalmente la base funcional y técnica del sistema local, incluyendo:

* Recepción y validación de solicitudes de trabajo.
* Generación de identificadores únicos para los trabajos.
* Administración de trabajos mediante cola e historial.
* Manejo de estados de los trabajos.
* Ejecución de trabajos mediante procesos independientes.
* Captura del código de salida, `stdout` y `stderr`.
* Cancelación de trabajos cuando la funcionalidad disponible lo permita.
* Manejo de entradas inválidas sin provocar la terminación del servicio.
* Construcción y ejecución reproducible del proyecto.
* Existencia y ejecución de pruebas automatizadas.

Las funcionalidades que todavía no formen parte de la implementación del Avance 1, como determinadas funciones de persistencia, recuperación, comunicación remota o restricciones de red, se mantendrán identificadas en la matriz de trazabilidad y se marcarán como **BLOCKED** o pendientes de implementación, según corresponda.

La verificación de estas funcionalidades se ampliará en los siguientes avances.

---

## 2. Requisitos que se verificarán

Los requisitos serán identificados mediante los códigos definidos para el proyecto:

* **RF-XX:** requisitos funcionales.
* **RNF-XX:** requisitos no funcionales.

Cada requisito deberá estar relacionado con al menos un método de verificación y, cuando corresponda, con uno o más casos de prueba.

La **matriz de trazabilidad** será el elemento principal para mantener esta relación:

> **Requisito → Método → Caso → Evidencia → Resultado**

Para el Avance 1 se dará prioridad a los requisitos relacionados con las funcionalidades actualmente implementadas y a los requisitos no funcionales necesarios para demostrar una construcción y ejecución reproducibles.

Los requisitos aún no implementados no serán considerados automáticamente como fallidos; su estado se registrará como **BLOCKED** cuando no sea posible realizar la verificación debido a una funcionalidad pendiente.

---

## 3. Métodos de verificación

Se utilizarán los siguientes métodos:

### 3.1 PRUEBA

Consiste en ejecutar el sistema o uno de sus componentes bajo condiciones controladas y comparar el resultado obtenido con el resultado esperado.

Se utilizará principalmente para:

* Funcionalidades del sistema.
* Pruebas automatizadas.
* Validación de entradas.
* Estados de los trabajos.
* Ejecución de procesos.
* Captura de resultados.
* Comportamiento ante errores.

### 3.2 ANÁLISIS

Consiste en evaluar información obtenida mediante cálculos, mediciones, resultados de pruebas o revisión de datos.

Se utilizará, por ejemplo, para:

* Analizar tiempos de ejecución.
* Verificar límites de concurrencia.
* Revisar resultados obtenidos durante las pruebas.
* Comparar resultados observados con criterios establecidos.

### 3.3 INSPECCIÓN

Consiste en revisar directamente elementos del proyecto sin necesidad de ejecutar el sistema.

Se utilizará para verificar:

* Código fuente.
* Estructura del repositorio.
* Documentación.
* Configuración.
* Archivos de construcción.
* Registros y decisiones de diseño.
* Cumplimiento de convenciones establecidas.

### 3.4 DEMOSTRACIÓN

Consiste en mostrar el comportamiento del sistema mediante una ejecución controlada.

La demostración se utilizará como complemento de la verificación, principalmente para presentar el funcionamiento del sistema durante las revisiones del proyecto.

Una demostración por sí sola no sustituye una prueba reproducible cuando el requisito requiere evidencia de ejecución formal.

---

## 4. Niveles de verificación

La verificación se realizará en diferentes niveles, dependiendo del requisito:

### Unit

Verificación de funciones o componentes individuales de forma aislada.

Ejemplos:

* Parser.
* Máquina de estados.
* Executor.
* Validaciones individuales.

### Integration

Verificación de la interacción entre dos o más componentes.

Ejemplos:

* Parser → Scheduler.
* Scheduler → State Machine.
* Executor → resultados de ejecución.

### System

Verificación del flujo completo del sistema desde la perspectiva de un usuario o cliente.

Ejemplo:

> Enviar trabajo → obtener ID → consultar estado → ejecutar → obtener resultado.

### Robustness

Verificación del comportamiento ante condiciones anormales o entradas inesperadas.

Ejemplos:

* Comandos inválidos.
* Procesos que terminan con error.
* Cancelaciones.
* Saturación de recursos.

### Security

Verificación de restricciones y controles relacionados con seguridad, permisos, interfaces y entradas no autorizadas.

### Acceptance

Verificación de que el sistema cumple los escenarios definidos para su aceptación por parte del usuario.

No todos los niveles deberán estar completamente implementados en Avance 1. El nivel utilizado deberá indicarse en cada caso de prueba.

---

## 5. Criterios de entrada

Antes de ejecutar formalmente un caso de verificación deberán cumplirse, cuando sean aplicables, los siguientes criterios:

* El código correspondiente se encuentra integrado en la rama candidata.
* El repositorio puede obtenerse mediante un clon limpio.
* El proyecto puede construirse mediante el procedimiento documentado.
* Los requisitos relacionados con el caso se encuentran identificados.
* El caso de prueba ha sido definido y revisado.
* El ambiente necesario para la ejecución se encuentra disponible.
* Las dependencias requeridas están instaladas.
* La versión o commit que será evaluado está identificado.
* No existen defectos conocidos que impidan la ejecución del caso, o estos se encuentran documentados como excepciones.

Si alguno de estos criterios no se cumple y esto impide realizar la prueba, el caso podrá registrarse como **BLOCKED**.

---

## 6. Criterios de salida

La verificación del Avance 1 se considerará completa cuando:

* Los requisitos incluidos en el alcance tengan trazabilidad.
* Los casos de prueba correspondientes estén documentados.
* Las pruebas automatizadas puedan ejecutarse mediante un procedimiento documentado.
* Las pruebas críticas dentro del alcance hayan sido ejecutadas.
* Los resultados de las pruebas cuenten con evidencia reproducible.
* Los resultados estén registrados como **PASS**, **FAIL** o **BLOCKED**.
* Los defectos encontrados estén registrados y relacionados con los casos correspondientes.
* Las limitaciones y funcionalidades pendientes estén documentadas.
* La matriz de trazabilidad se encuentre actualizada.
* La versión o commit evaluado esté identificado.

Un requisito que todavía no pueda verificarse por falta de implementación no será considerado PASS; deberá permanecer como **BLOCKED** hasta que exista una implementación que permita ejecutar su verificación.

---

## 7. Ambiente controlado

Cada ejecución de verificación deberá registrar la información necesaria para reproducirla.

Como mínimo se registrará:

* Sistema operativo y versión.
* Arquitectura del sistema.
* Versión del compilador y herramientas relevantes.
* Versión de Rust/Cargo.
* Dependencias utilizadas.
* Commit o versión del proyecto evaluada.
* Configuración relevante del sistema.
* Parámetros de ejecución utilizados.
* Fecha de ejecución.

Cuando una prueba requiera condiciones específicas, estas deberán indicarse en el caso de prueba correspondiente.

La información del ambiente podrá almacenarse como parte de la evidencia en:

```text
verif/results/<fecha>/<TC-XXX>/environment.txt
```

---

## 8. Evidencias esperadas

Cada ejecución deberá producir evidencia suficiente para demostrar el resultado obtenido.

Dependiendo del caso, podrán utilizarse:

* Salida de pruebas automatizadas.
* Logs.
* Resultados de ejecución.
* Archivos de configuración.
* Mediciones.
* Capturas de pantalla cuando aporten información relevante.
* Hash del commit evaluado.
* Información del ambiente.
* Reportes de ejecución.
* Resultados generados por scripts.

La evidencia deberá permitir identificar como mínimo:

* Caso de prueba.
* Fecha de ejecución.
* Ambiente.
* Versión o commit evaluado.
* Resultado obtenido.

Las evidencias se almacenarán dentro de:

```text
verif/results/
```

utilizando una organización por fecha y caso de prueba.

Ejemplo:

```text
verif/results/
└── 2026-10-03/
    ├── TC-001/
    │   ├── environment.txt
    │   ├── test-output.txt
    │   └── summary.md
    └── TC-006/
        ├── environment.txt
        ├── test-output.txt
        └── summary.md
```

---

## 9. Manejo de PASS / FAIL / BLOCKED

Cada caso de prueba deberá finalizar con uno de los siguientes estados:

### PASS

El comportamiento observado cumple con el resultado esperado y existe evidencia suficiente para demostrarlo.

### FAIL

La funcionalidad pudo ejecutarse, pero el comportamiento observado no cumple con el resultado esperado.

Todo **FAIL** deberá generar o relacionarse con un Issue que documente:

* Caso afectado.
* Requisito relacionado.
* Pasos para reproducir.
* Resultado esperado.
* Resultado observado.
* Evidencia.
* Severidad.

Después de corregir el defecto, el caso deberá ejecutarse nuevamente.

### BLOCKED

El caso no puede ejecutarse o concluirse debido a una dependencia, funcionalidad pendiente, problema de ambiente u otra condición externa al resultado que se pretende verificar.

El estado BLOCKED deberá indicar claramente la causa y, cuando sea posible, el Issue o actividad relacionada.

**BLOCKED no equivale a FAIL:** significa que todavía no existe una condición válida para determinar si el requisito cumple o no.

---

## 10. Relación requisito → caso → evidencia

La trazabilidad se mantendrá mediante la matriz ubicada en:

```text
verif/verification-plan/traceability-matrix.md
```

La matriz deberá permitir identificar:

| Req ID | Descripción breve                 | Prioridad | Método | Caso(s) | Evidencia | Resultado | Defecto/Excepción        |
| ------ | --------------------------------- | --------- | ------ | ------- | --------- | --------- | ------------------------ |
| RF-01  | Enviar trabajo y obtener ID único | Alta      | PRUEBA | TC-001  | Pendiente | BLOCKED   | Flujo completo pendiente |
| RF-02  | Validar solicitud                 | Alta      | PRUEBA | TC-001  | Pendiente | BLOCKED   | Integración pendiente    |
| RF-06  | Estados del trabajo               | Alta      | PRUEBA | TC-003  | Pendiente | Pendiente | —                        |
| RF-11  | Capturar stdout/stderr            | Alta      | PRUEBA | TC-006  | Pendiente | Pendiente | —                        |

La matriz se actualizará conforme avance la implementación y después de cada ejecución formal.

El objetivo final es mantener una cadena de trazabilidad completa:

> **Requisito → Método de verificación → Caso de prueba → Ejecución → Evidencia → Resultado**

Esto permite determinar qué requisitos han sido verificados, cuáles presentan defectos y cuáles todavía se encuentran pendientes de implementación o verificación.
