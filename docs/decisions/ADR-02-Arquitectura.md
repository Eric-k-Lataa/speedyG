# ADR-02: Selección de la Arquitectura

## Contexto

SpeedyG necesita una arquitectura base para su motor de ejecución capaz de gestionar múltiples trabajos concurrentes, 
coordinar transiciones de estado, manejar eventos de E/S del sistema operativo y garantizar un rendimiento predecible 
sin interbloqueos ni uso excesivo de recursos.

## Alternativas consideradas

### Tuberías y Filtros (Pipes & Filters)

**Ventajas:**
- Flujo de datos desacoplado y altamente modular entre etapas de procesamiento
- Facilidad para probar, reemplazar o agregar filtros individuales de forma aislada
- Reutilización directa de componentes del pipeline
  
**Desventajas:**
- Dificultad para manejar estados globales compartidos o transiciones dinámicas entre procesos
- Complejidad para gestionar cancelaciones y manejo de errores asíncronos en tiempo real
- Overhead de latencia por la transferencia continua de datos/contexto entre etapas

### Arquitectura Basada en Eventos

**Ventajas:**
- Alto nivel de desacoplamiento entre emisores y receptores mediante canales o un bus
- Excelente capacidad de escalabilidad vertical y concurrencia asíncrona
- Respuesta rápida ante eventos externos e interrupciones del sistema

**Desventajas:**
- Riesgo de alta complejidad estructural (callback hell o rastreo de eventos dispersos)
- No determinismo explícito en los cambios de estado si no se controla adecuadamente
- Mayor dificultad para depurar la secuencia exacta de ejecuciones en fallos de concurrencia

### Bucle de Eventos con Máquina de Estados Finitos (Event Loop + FSM)

**Ventajas:**
- Determinismo riguroso: las transiciones de estado de cada trabajo están estrictamente definidas por la FSM
- Uso eficiente de recursos: un Event Loop asíncrono no bloqueante reduce el sobrecoste de contexto (context switching)
- Control preciso sobre la concurrencia, cancelación y gestión de ciclos de vida de los procesos en Linux

**Desventajas:**
- Mayor esfuerzo de diseño inicial para modelar la FSM y la infraestructura del Event Loop
- Requiere un manejo cuidadoso para evitar bloqueos en el hilo principal del Event Loop

## Decisión

Se selecciona **Bucle de Eventos con FSM (Event Loop + FSM)** como la arquitectura del nucleo de SpeedyG.
Se tomo esta decisión debido a que la combinación de un bucle de eventos reactivo con máquinas de estado explícitas 
proporciona el control determinista, la concurrencia eficiente y el manejo transparente de señales/procesos en Linux 
que el proyecto exige.

## Consecuencias

### Alternativas consideradas

#### Tuberías y Filtros

**Positivas**

- Procesamiento modular y aislado de las fases de ejecución del trabajo

**Negativas**

- Falta de flexibilidad para la gestión centralizada de estados y cancelaciones repentinas
- Estructura rígida que dificulta la comunicación bidireccional entre componentes

**Riesgos**

- Cuellos de botella en la transferencia entre filtros que degraden el rendimiento del motor

#### Arquitectura Basada en Eventos

**Positivas**

- Desacoplamiento total y respuesta ágil ante interrupciones o cambios de estado

**Negativas**

- Dificultad para garantizar la secuencia exacta de estados por los que pasa un trabajo

**Riesgos**

- Pérdida de trazabilidad o condiciones de carrera si las emisiones de eventos no están fuertemente reguladas

#### Bucle de Eventos con FSM (Seleccionada)

**Positivas**

- Garantía de consistencia: un trabajo solo puede estar en un estado válido a la vez
- Minimiza la contención de hilos y el consumo de CPU/memoria bajo alta carga
- Facilita la implementación de timeouts, reintentos y cancelaciones seguras

**Negativas**

- Curva de aprendizaje y complejidad de implementación inicial superior

**Riesgos**

- Tareas bloqueantes ejecutadas dentro del bucle de eventos podrían degradar la latencia general si no se delegan
correctamente a hilos secundarios o canales MPSC

## Requisitos afectados

### Alternativas consideradas

#### Tuberías y Filtros
- +RF-01 : Permite dividir el procesamiento en etapas secuenciales
- -RF-05 : Dificulta la supervisión y detención inmediata de tareas en ejecución

- -RNF-01 : Rendimiento limitado por la sincronización entre etapas del pipeline
- -RNF-04 : Mayor complejidad para garantizar estados consistentes ante fallos abruptos

#### Arquitectura Basada en Eventos
- +RF-04 : Manejo nativo de notificaciones y eventos asíncronos del sistema
- +RF-05 : Facilita la emisión de señales de cancelación distribuidas

- -RNF-02 : Menor determinismo en los tiempos de respuesta y orden de ejecución
- -RNF-04 : Requiere lógica adicional para reconstruir el estado exacto tras una falla

#### Bucle de Eventos con FSM
- +RF-01 : Control preciso del ciclo de vida y ejecución de cada trabajo
- +RF-05 : Permite transicionar de forma segura a estados de cancelación mediante el Event Loop
- +RF-07 : Facilita el monitoreo del estado actual de cualquier trabajo en tiempo real

- +RNF-01 : Alta eficiencia en el uso de recursos y baja latencia de respuesta
- +RNF-02 : Comportamiento determinista frente a eventos concurrentes
- +RNF-04 : Transiciones de estado robustas que previenen inconsistencias ante fallos
