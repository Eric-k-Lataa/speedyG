# ADR-01: Lenguaje de programación

## Contexto
El proyecto SpeedyG requiere un lenguaje de programación que permita concurrencia, manejo de procesos y comunicación de red de manera segura y eficiente.

## Alternativas consideradas

### C/C++

**Ventajas:**
- Rendimiento muy alto, ya que el código se compila a binario nativo y maximiza los recursos.  
- Control directo sobre hilos y concurrencia.  
- Mayor control sobre las llamadas al sistema operativo; es el lenguaje “natural” para trabajar a bajo nivel.  
- Amplia comunidad y documentación sólida.  

**Desventajas:**
- Propenso a memory leaks y race conditions.  
- Complejidad que puede afectar el desarrollo del proyecto.  
- La gestión manual de colas concurrentes requiere más código y tiempo.  
- El mal uso de mutexes puede causar deadlocks.  
- Uso de bibliotecas externas y configuración más compleja.  

### Rust

**Ventajas:**
- Rendimiento cercano a C/C++ con control de bajo nivel.  
- Seguridad de memoria sin necesidad de recolector de basura.  
- Concurrencia segura, sin condiciones de carrera.  
- Cargo: gestor de paquetes moderno y eficiente.  
- Ecosistema en crecimiento y soporte multiplataforma.  

**Desventajas:**
- Ninguno de los integrantes del equipo tiene experiencia previa con Rust.  
- La compilación es más lenta debido a las verificaciones de seguridad y optimización.  
- Menor cantidad de librerías maduras comparado con C/C++.  

## Decisión
Se selecciona Rust como lenguaje principal para construir SpeedyG en Debian (Linux).

### Razones técnicas:
- Seguridad de gestión de memoria mediante ownership y borrow checker, que detectan errores en tiempo de compilación.  
- Concurrencia segura que evita modificaciones simultáneas inseguras.  
- Ecosistema adecuado para el proyecto y soporte multiplataforma.  
- Sugerencia del profesor y motivación del equipo por aprender un lenguaje moderno.  

## Consecuencias

### C/C++

**Positivas:**
- Rendimiento y latencia predecible al ser un lenguaje nativo.  
- Control total sobre recursos como hilos, memoria y llamadas al sistema operativo.  
- Amplia documentación y soporte.  

**Negativas:**
- Manejo de memoria complejo.  
- Código más propenso a errores.  

**Riesgos:**
- Memory leaks por liberación incorrecta de memoria.  
- Errores de segmentación al acceder a punteros inválidos.  
- Race conditions difíciles de detectar.  

### Rust

**Positivas:**
- Menor riesgo de bugs, race conditions y memory leaks.  
- Concurrencia segura.  
- Ecosistema moderno y gestor de paquetes eficiente.  
- Buen balance entre rendimiento y seguridad.  

**Negativas:**
- Tiempos de compilación prolongados.  
- Curva de aprendizaje alta.  
- Menos librerías maduras que C/C++.  

**Riesgos:**
- Necesidad de configurar correctamente el entorno en Debian.  
- Dependencia de bibliotecas externas, cuya calidad puede variar.  

## Requisitos afectados

### C/C++
- +RF-01: Control directo sobre procesos y llamadas al sistema.  
- +RF-02: Manejo eficiente de archivos y salidas.  
- -RF-03: Concurrencia más compleja y manual.  
- +RF-04: Ejecución de trabajos como procesos separados, aunque protocolos de red más complejos.  
- +RNF-01: Rendimiento muy alto al compilar nativamente en Linux.  
- -RNF-05: Acceso directo a memoria favorece rapidez, pero compromete estabilidad.  
- -RNF-07: Mayor probabilidad de race conditions.  
- -RNF-08: Errores de memoria pueden congelar el proyecto.  
- -RNF-09: Poco aislamiento de memoria entre módulos, riesgo de corrupción.  
- -RNF-33: Mayor probabilidad de fugas de memoria.  

### Rust
- +RF-01: Concurrencia segura.  
- +RF-02: Manejo de procesos con seguridad de memoria.  
- -RF-05: Compilación más lenta, aunque ejecución eficiente.  
- +RNF-01: Lenguaje estable y fiable.  
- +RNF-04: Concurrencia segura respeta límites sin condiciones de carrera.  
- +RNF-08: Mejor control y manejo de errores.  
- +RNF-09: Ownership impide corrupción entre módulos y reduce efectos de fallos.  
- +RNF-10: Buen rendimiento con balance entre seguridad y velocidad.  
- +RNF-30: Reduce el riesgo de procesos huérfanos.  

