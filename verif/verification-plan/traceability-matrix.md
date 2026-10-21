# Matrix de trazabilidad

| Req ID    | Descripción breve | Prioridad | Método | Caso(s) | Evidencia | Resultado | Defecto/Excepción |
|:------------|:------------------|:---------:|:------:|:----------|:----------|:---------:|:------------------|
| RF-01     | Enviar trabajo e ID único | Alta | PRUEBA | TC-001 | resultado + log      | PASS | —|
| RF-02     | Validar solicitud con mensaje útil | Alta | PRUEBA | TC-001 | resultado + log | PASS | —|
| RF-03     | Mantener una cola | Alta | Prueba | TC-002 | resultado + log | Pendiente | —|
| RF-04     | Procesos independientes | Alta | Prueba | TC-001 | estados + log | PASS | —|
| RF-05     | Límite de concurrencia    | Alta | Prueba | TC-002 | timeline + ps/log | Pendiente | —|
| RF-06     | Estados de un trabajo | Alta | Prueba | TC-003 | timeline + ps/log  | Pendiente | —|
| RF-07     | Registrar timers y còdigo de salida | Alta | Prueba | TC-003, TC-006 | resultado + log | Pendiente | —|
| RF-08     | Consulta | Alta | Prueba | TC-004 | estados + señal | Pendiente | —|
| RF-09     | Lista | Alta | Prueba | TC-004 | estados + señal | Pendiente | —|
| RF-10     | Cancelación | Alta | Prueba | TC-005 | estados + señal | Pendiente | —|
| RF-11     | Consultar stdout y stderr | Alta | Prueba | TC-006 | resultado + log | Pendiente | —|
| RNF-01    | Compilar y ejecutar en linux | Alta | Prueba | TC-014 | resultado + log | Pendiente | —|
| RNF-02    | Construcción reproducible | Alta | Prueba/Inspeccioń | TC-014 | log de build | Pendiente | —|
| RNF-03    | Còdigo sin privilegios de root | Alta | Prueba | TC-014 | - | Pendiente | —|
| RNF-04    | Limitar trabajos simultáneos | Alta | Prueba | TC-002 | resultado + log | Pendiente | —|
| RNF-05    | Consulta de estado 1s/100 | Alta | Prueba | TC-004 | resultado + log | Pendiente | —|
| RNF-06    | Soportar al menos 500 registros | Alta | Prueba | TC- | resultado + log | Pendiente | —|
| RNF-07    | Cola y limite de concurrencia sincronizados | Alta | Prueba | TC-002 | resultado + log | Pendiente | —|
| RNF-08    | Solicitud inválida o desconexioń de cliente y se mantiene el servicio | Alta | Prueba | TC-008 | resultado + log | Pendiente | —|
| RNF-09    | Aislamiento de fallo  | Alta | Prueba | TC-008 | log + estados | Pendiente | —|
| RNF-10    | Condiciones de reinicio | Alta | Prueba | TC-007 | resultado + log | Pendiente | —|
| RNF-11    | Condición para archivos persistentes | Alta | Prueba | TC-007 | resultado + log | Pendiente | —|
