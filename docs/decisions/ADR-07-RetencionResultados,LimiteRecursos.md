# ADR-07: Política de retención de resultados y límites de recursos

## Contexto

Actualmente, SpeedyG almacena los metadatos y las salidas (`stdout` y `stderr`) de los trabajos ejecutados en SQLite, pero no cuenta con límites definidos para el tamaño de las salidas ni para la cantidad de registros conservados en el historial.

Es necesario establecer límites para controlar el consumo de memoria y almacenamiento, definir cómo se eliminan los registros antiguos y determinar el comportamiento del sistema cuando se alcanzan dichos límites.

## Alternativas consideradas

### 1. Retención del historial

**Alternativa A: Conservar un máximo de 500 trabajos terminados**

**Ventajas:**
- Cumple con el mínimo de 500 registros establecido por RNF-06
- Limita el espacio de almacenamiento destinado al historial

**Desventajas:**
- Ofrece poco margen para conservar trabajos anteriores
- Los registros más antiguos se eliminan con mayor frecuencia

**Alternativa B: Conservar un máximo de 1000 trabajos terminados**

**Ventajas:**
- Supera el mínimo de 500 registros establecido por RNF-06
- Permite conservar un historial más amplio para consultar trabajos anteriores

**Desventajas:**
- Requiere más espacio de almacenamiento
- Incrementa la cantidad de registros que deben gestionarse durante las consultas y operaciones de persistencia

### 2. Límite de salida por trabajo

**Alternativa A: Establecer un límite de 512 KiB combinados entre `stdout` y `stderr`**

**Ventajas:**
- Reduce el espacio de almacenamiento utilizado por cada trabajo
- Limita la cantidad de salida que debe conservarse y recuperarse

**Desventajas:**
- Puede resultar insuficiente para trabajos que producen salidas extensas
- Aumenta la probabilidad de perder información útil por truncamiento

**Alternativa B: Establecer un límite de 1 MB combinado entre `stdout` y `stderr`**

**Ventajas:**
- Permite conservar una mayor cantidad de información de cada trabajo
- Mantiene un límite definido para controlar el consumo de memoria y almacenamiento

**Desventajas:**
- Requiere más espacio de almacenamiento que un límite de 512 KiB
- Puede incrementar el consumo de recursos cuando se conservan muchas salidas cercanas al límite

### 3. Comportamiento cuando se supera el límite de salida

**Alternativa A: Cancelar el trabajo cuando supere el límite de salida**

**Ventajas:**
- Evita que el trabajo continúe generando grandes cantidades de salida
- Permite mantener el consumo de recursos bajo control

**Desventajas:**
- Interrumpe trabajos que podrían ejecutarse correctamente
- Una salida extensa no necesariamente significa que el trabajo tenga un problema

**Alternativa B: Truncar la salida y permitir que el trabajo continúe**

**Ventajas:**
- Evita interrumpir trabajos que generan grandes cantidades de salida
- Conserva una parte de la información generada para su consulta
- Mantiene limitado el almacenamiento utilizado por cada trabajo

**Desventajas:**
- Se pierde la parte de la salida que supera el límite
- Es necesario informar al cliente que la salida fue truncada

### 4. Eliminación de registros al alcanzar el límite del historial

**Alternativa A: Eliminar automáticamente los trabajos terminados más antiguos**

**Ventajas:**
- Mantiene el historial dentro del límite establecido
- Permite aceptar nuevos trabajos sin requerir intervención manual
- Evita el crecimiento indefinido del almacenamiento

**Desventajas:**
- Los resultados más antiguos dejan de estar disponibles para consulta
- La eliminación automática puede provocar la pérdida de información que el usuario todavía necesite

**Alternativa B: Rechazar nuevos trabajos hasta que se eliminen registros manualmente**

**Ventajas:**
- Evita eliminar resultados sin intervención del usuario
- Permite conservar los registros existentes hasta que se decida cuáles eliminar

**Desventajas:**
- Requiere intervención manual para liberar espacio
- Puede impedir el envío de nuevos trabajos aunque el servicio siga funcionando

## Decisión

Se proponen las siguientes decisiones para SpeedyG:

1. El historial conservará un máximo de **1000 trabajos terminados**. Este límite permitirá superar la capacidad mínima de 500 registros establecida por RNF-06. **Caso de aceptación: TC-007**
2. Cada trabajo tendrá un límite máximo de **1 MB combinado entre `stdout` y `stderr`** para controlar el consumo de memoria y almacenamiento. **Caso de aceptación: TC-006**
3. Cuando la salida supere el límite establecido, SpeedyG conservará los primeros bytes hasta alcanzar 1 MB, descartará el excedente y permitirá que el trabajo continúe. El cliente deberá recibir una indicación de que la salida fue truncada. **Caso de aceptación: TC-006**
4. Cuando el historial alcance los 1000 trabajos terminados y finalice un nuevo trabajo, se eliminará automáticamente el registro terminado más antiguo para conservar el límite establecido. Los trabajos en cola y en ejecución no se eliminarán mediante esta política. **Caso de aceptación: TC-007**

## Consecuencias

### Positivas

- El historial tiene un límite definido de 1000 trabajos terminados, evitando el crecimiento indefinido de registros
- La capacidad establecida supera el mínimo de 500 registros requerido por RNF-06
- El tamaño máximo de salida por trabajo permite controlar el consumo de memoria y almacenamiento
- El truncamiento permite que los trabajos continúen ejecutándose aunque generen grandes cantidades de salida
- La eliminación automática de registros antiguos permite mantener disponible el servicio sin requerir intervención manual
- Los trabajos pendientes y en ejecución se mantienen protegidos frente a la política de eliminación del historial

### Negativas

- Los resultados más antiguos pueden dejar de estar disponibles cuando se alcanza el límite del historial
- El truncamiento provoca que parte de la salida generada por un trabajo no pueda consultarse posteriormente
- La captura limitada de `stdout` y `stderr` requiere una implementación que controle el consumo de memoria durante la ejecución
- Es necesario mantener sincronizados los registros del historial en memoria y en SQLite para evitar inconsistencias

## Riesgos

- Si el límite de 1000 trabajos no se aplica correctamente, el historial podría superar la capacidad establecida y provocar un crecimiento excesivo del almacenamiento
- Si la eliminación automática no se sincroniza entre el `Scheduler` y SQLite, podrían aparecer diferencias entre los registros en memoria y los persistidos
- Si el límite de salida se aplica después de capturar toda la información del proceso, el consumo de memoria podría superar el máximo previsto
- Si el truncamiento no se informa correctamente al cliente, el usuario podría interpretar una salida incompleta como si fuera el resultado completo del trabajo
- Si la eliminación automática selecciona incorrectamente los registros, podrían perderse resultados recientes o eliminarse trabajos que todavía se encuentran en ejecución
- Si la captura de `stdout` y `stderr` no se realiza correctamente, alguno de los flujos podría bloquear al proceso o perder información antes de alcanzar el límite establecido

## Requisitos afectados

**Retención máxima de 1000 trabajos terminados**
- +RF-12: Conserva metadatos y resultados después de reiniciar el servicio
- +RF-13: Requiere recuperar el historial persistido al iniciar el servicio
- +RNF-06: Establece la capacidad mínima de 500 registros sin pérdida de metadatos

**Límite de 1 MB combinado entre `stdout` y `stderr`**
- +RF-11: Permite capturar y consultar las salidas de los trabajos
- +RNF-29: Ayuda a controlar el consumo de memoria y almacenamiento mediante límites de recursos

**Truncamiento de salida al superar el límite**
- +RF-11: Permite consultar las salidas de los trabajos, aunque estas hayan sido truncadas
- +RF-23: Permite rechazar y registrar solicitudes que excedan los límites configurados
- +RNF-29: Ayuda a controlar el consumo de recursos cuando se alcanzan los límites establecidos

**Eliminación automática de los trabajos terminados más antiguos**
- +RF-12: Define la conservación de metadatos y resultados después de reiniciar el servicio
- +RF-13: Requiere recuperar el historial persistido al iniciar el servicio
- +RNF-06: Establece la cantidad mínima de registros que deben conservarse sin pérdida de metadatos

### Evidencia y prototipo de referencia
- Estado actual del repositorio: captura de `stdout` y `stderr` en `src/executor.rs`, almacenamiento de resultados y metadatos en `src/state_machine.rs` y `src/scheduler.rs`, y persistencia del historial en SQLite mediante `src/persistence.rs`.
- Casos de prueba TC-006 y TC-007 para validar los límites de salida por trabajo, el truncamiento de resultados y la retención máxima de 1000 trabajos terminados.