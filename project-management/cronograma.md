# Cronograma de desarrollo SpeedyG
El archivo se llama cronograma pero tecnicamente es un roadmap de ruta critica :)

| ID  | Tarea   | Dependencia | Duración (en días) |
|:--- |:---------------:|:-------:|:---:|
|1    | Desarrollo FSM y sus transiciones | - | 5 |
|2    | Pruebas unitarias FSM | 1 | 2 |
|3    | Definición de Protocolo JSON | 1 | 2 |
|4    | Infraestructura del Event Loop | 2 | 5 |
|5    | Canales de Comunicación MPSC | 4 | 4 |
|6    | Llamada de Procesos Linux | 5 | 7 |
|7    | Gestión de Grupos de Proceso | 6 | 4 |
|8    | Lógica de Cancélación y Escalamiento | 7 | 5 |
|9    | Pruebas de Concurrencia e Inyección de Fallos | 3, 8 | 5 |

# Roadmap de Desarrollo Técnico - SpeedyG (versión grafica)

```mermaid
graph TD
    classDef critical fill:#ffebee,stroke:#c62828,stroke-width:3px,color:#b71c1c;
    classDef float fill:#e1f5fe,stroke:#0288d1,stroke-width:2px,color:#01579b;

    T1["<b>T1: Desarrollo FSM y Transiciones</b><br/>Duración: 5d | Holgura: 0d"]:::critical
    T2["<b>T2: Pruebas Unitarias FSM</b><br/>Duración: 2d | Holgura: 0d"]:::critical
    T4["<b>T4: Infraestructura Event Loop</b><br/>Duración: 5d | Holgura: 0d"]:::critical
    T5["<b>T5: Canales MPSC</b><br/>Duración: 4d | Holgura: 0d"]:::critical
    T6["<b>T6: Llamada Procesos Linux</b><br/>Duración: 7d | Holgura: 0d"]:::critical
    T7["<b>T7: Gestión Grupos Proceso (PGID)</b><br/>Duración: 4d | Holgura: 0d"]:::critical
    T8["<b>T8: Cancelación y Escalamiento</b><br/>Duración: 5d | Holgura: 0d"]:::critical
    T9["<b>T9: Pruebas Concurrencia y Fallos</b><br/>Duración: 5d | Holgura: 0d"]:::critical

    T3["<b>T3: Definición Protocolo JSON</b><br/>Duración: 2d | Holgura: 22d"]:::float

    T1 ==> T2
    T2 ==> T4
    T4 ==> T5
    T5 ==> T6
    T6 ==> T7
    T7 ==> T8
    T8 ==> T9

    T1 -.-> T3
    T3 -.-> T9
```
