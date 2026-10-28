# ADR-04: Cancelación, escalamiento, duplicados y saturación

## Contexto 

SpeedyG necesita definir el comportamiento del sistema cuando la cola alcanza su capacidad máxima, se reciben solicitudes duplicadas, se cancelan trabajos y los procesos no terminan normalmente. También es necesario establecer cómo se manejan las cancelaciones concurrentes y cuánto tiempo se conservan los resultados.

Estas decisiones deben garantizar la consistencia de los estados, evitar procesos huérfanos y proporcionar respuestas claras a los clientes

## Alternativas  consideradas

### 1. Capacidad de la cola y saturación

**Alternativa A: Cola con capacidad máxima de 5 trabajos en espera**
 
**Ventajas:**
- Permite aceptar más trabajos pendientes antes de alcanzar la saturación
- Reduce los rechazos cuando aumenta temporalmente la demanda
- Mantiene un límite definido para controlar el consumo de recursos

**Desventajas:**
- Puede consumir más recursos al mantener más trabajos pendientes
- Los trabajos pueden tardar más en comenzar a ejecutarse cuando la cola está llena

**Alternativa B: Cola con capacidad máxima de 3 trabajos en espera**

**Ventajas:**
- Limita el consumo de recursos asociado a los trabajos pendientes
- Permite detectar la saturación y responder explícitamente
- Los trabajos que ya fueron aceptados no se pierden por recibir nuevas solicitudes

**Desventajas:**
- Los nuevos trabajos se rechazan cuando la cola está llena
- El cliente debe volver a enviar una solicitud rechaza si desea intentarlo posteriormente 

## 2. Tratamiento de solicitudes duplicadas 

**Alternativa A: Aceptar cada solicitud como un trabajo independiente**
**Ventajas:**
- No requiere modificar el protocolo para identificar solicitudes
- Es sencilla de implementar

**Desventajas:**
- Un reintento puede ejecutar el mismo comando más de una vez
- El cliente puede generar trabajos adicionales si no sabe si su primera solicitud fue aceptada

**Alternativa B: Identificar solicitudes mediante un `request-id` único**

**Ventajas:**
- Permite reconocer los reintentos de una misma solicitud
- Evita crear un nuevo trabajo cuando se recibe nuevamente una solicitud ya registrada
- Facilita relacionar las respuestas con la solicitud original

**Desventajas:**
- Requiere modificar el protocolo para incluir el identificador
- Es necesario conservar la relación entre el identificador de solicitud y el trabajo correspondiente

## 3. Política de cancelación y escalamiento

**Alternativa A: Enviar únicamente SIGTERM**

**Ventajas:**
- Permite que el proceso termine de forma controlada
- Le da oportunidad de realizar tareas de limpieza

**Desventajas:**
- El proceso puede ignorar la señal o no terminar
- No garantiza que el trabajo se detenga dentro de un tiempo definido

**Alternativa B: Enviar SIGTERM y después SIGKILL**

**Ventajas:**
- Permite intentar una terminación controlada antes de forzarla
- Establece un límite de tiempo para detener el trabajo
- Reduce el riesgo de mantener procesos activos indefinidamente

**Desventajas:**
- SIGKILL no permite que el proceso realice su limpieza habitual
- Debe definirse un tiempo de espera configurable

## 4. Alcance de las señales

**Alternativa A: Enviar señales únicamente al proceso principal**

**Ventajas:**
- La implementación es más sencilla
- Permite controlar directamente el proceso iniciado por el ejecutor

**Desventajas:**
- Los procesos hijos podrían continuar ejecutándose
- Aumenta el riesgo de dejar procesos huérfanos

**Alternativa B: Enviar señales al grupo de procesos del trabajo**

**Ventajas:**
- Permite terminar el proceso principal y sus procesos descendientes que pertenezcan al grupo
- Facilita la limpieza de los recursos asociados al trabajo

**Desventajas:**
- Requiere crear y gestionar correctamente los grupos de procesos
- Debe evitarse enviar señales a procesos que no pertenezcan al trabajo

## 5. Cancelaciones concurrentes

**Alternativa A: Procesar las solicitudes de cancelación de forma serializada**

**Ventajas:**
- Una única solicitud inicia la cancelación
- Las solicitudes posteriores pueden recibir el estado actualizado del trabajo
- Facilita mantener transiciones de estado consistentes

**Desventajas:**
- Las solicitudes concurrentes deben esperar su turno de procesamiento

**Alternativa B: Permitir que cada solicitud intente cancelar el trabajo de manera independiente**

**Ventajas:**
- Las solicitudes pueden comenzar a procesarse inmediatamente

**Desventajas:**
- Varias solicitudes podrían intentar terminar el mismo proceso
- Aumenta el riesgo de respuestas inconsistentes y transiciones duplicadas

## 6. Retención de resultados

**Alternativa A: Eliminar resultados automáticamente después de un periodo**

**Ventajas:**
- Limita el crecimiento de almacenamiento
- Reduce la necesidad de mantenimiento manual

**Desventajas:**
- Los resultados pueden desaparecer antes de que el usuario los consulte
- El periodo de retención debe configurarse y documentarse

**Alternativa B: Conservar los resultados hasta su eliminación manual**

**Ventajas:**
- Permite consultar el historial sin un limite temporal
- Evita la pérdida automática de resultados

**Desventajas:**
- El almacenamiento puede crecer con el tiempo
- Es necesario disponer de un mecanismo de eliminación manual

## Decisión 

Se proponen las siguientes decisiones SpeedyG:

1. La cola tendrá una capacidad máxima de 3 trabajos en espera, independientemente de los trabajos que se encuentren ejecutándose. Cuando esté llena, las nuevas solicitudes serán rechazadas explícitamente y sin bloquear indefinidamente al cliente. **Caso de aceptación: TC-016**
2. Las solicitudes duplicadas se tratarán como trabajos independientes. Cada solicitud recibida creará un nuevo trabajo, aunque tenga el mismo comando que otro trabajo enviado anteriormente. No se implementará un mecanismo para detectar duplicados **Caso de aceptación: TC-018**
3. La cancelación enviará SIGTERM** al grupo de procesos del trabajo. Si el trabajo no termina dentro de un tiempo configurable, se enviará SIGKILL **Caso de aceptación: TC-021**
4. Las señales se enviarán al grupo de procesos completo del trabajo, incluyendo el proceso principal y sus procesos hijos, para evitar que queden procesos ejecutándose después de cancelar el trabajo **Caso de aceptación: TC-021**
5. Las solicitudes de cancelación sobre un mismo trabajo se procesarán de forma serializada. La primera solicitud valida iniciará la cancelación y las giuientes recibirán una respuesta que indique si la cancelación sigue en curso o si la cancelación se completó **Caso de aceptación: TC-017**
6. Los resultados se conservarán permanentemente hasta que un usuario autorizado los elimine manualmente.

## Consecuencias

### Positivas

- La cola tiene un límite conocido y las solicitudes reciben una respuesta explícita cuando está llena
- Las solicitudes idénticas se procesan con una semántica sencilla y predecible: cada una representa un trabajo independiente
- La cancelación dispone de un mecanismo de escalamiento si el trabajo no termina voluntariamente
- El uso de grupos de procesos permite dirigir las señales al proceso principal y a sus hijos
- La serialización de cancelaciones facilita mantener estados consistentes ante solicitudes concurrentes
- Los resultados permanecen disponibles hasta que un usuario autorizado los elimine

### Negativas

- Una cola limitada puede rechazar trabajos legitimos durante periodos de alta demanda
- Los reintentos de clientes pueden generar trabajos repetidos y consumir recursos adicionales
- `SIGKILL` termina los procesos de forma forzada y no permite realizar tareas de limpieza dentro de ellos.
- La gestión de grupos de procesos requiere identificar y controlar correctamente los procesos asociados a cada trabajo
- La serialización de cancelaciones requiere coordinar el acceso al estado compartido 
- La conservación permanente puede incrementar el uso de almacenamiento con el tiempo

## Riesgos
- Una comprobación incorrecta de la capacidad de la cola podría permitir aceptar más trabajos de los establecidos.
- Al aceptar solicitudes duplicadas, un mismo comando podría ejecutarse varias veces y provocar cambios no deseados
- Si el grupo de procesos no se configura correctamente, la cancelación podría afectar procesos ajenos al trabajo o dejar procesos hijos activos.
- Si un trabajo termina justo cuando se está intentando cancelar, el sistema podría intentar detenerlo nuevamente o mostrar un estado incorrecto
- Si varias cancelaciones se procesan al mismo tiempo sin coordinación, el estado final del trabajo podría no coincidir con las respuestas enviadas a los clientes
- Si los resultados se eliminan manualmente por error, podría perderse información útil para revisar qué ocurrió durante la ejecución de un trabajo



## Requisitos afectados
**Capacidad máxima de la cola**
- +RF-25: Establece un límite de trabajos en espera y permite rechazar solicitudes cuando la cola está llena
- +RF-23: Permite rechazar solicitudes que excedan los límites configurados y registrarlas
- +RNF-29: Ayuda a controlar la saturación de recursos

**Solicitudes duplicadas como trabajos independientes**
- +RF-27: Define cómo se tratarán las solicitudes duplicadas o reenviadas, considerando cada solicitud aceptada como un trabajo independiente

**SIGTERM seguido de SIGKILL**
- +RF-10: Define cómo detener trabajos mediante una solicitud de cancelación
- +RF-30: Establece cómo actuar si un trabajo no termina con la cancelación normal

**Señales al grupo de procesos**
- +RNF-30: Ayuda a evitar que queden procesos hijos ejecutándose después de cancelar un trabajo

 **Cancelaciones procesadas de forma serializada**
- +RF-26: Permite responder de manera coherente ante solicitudes simultáneas de cancelación
- +RNF-27: Ayuda a mantener estados consistentes cuando varias solicitudes actúan sobre el mismo trabajo

**Conservación permanente de resultados**
- +RF-12: Conserva metadatos y resultados después de reiniciar el servicio.
- +RF-13: Requiere recuperar el historial persistido al iniciar el servicio.
