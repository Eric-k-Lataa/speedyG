# ADR-03: Mecanismo de persistencia

## Contexto

speedyG necesita almacenar la información de los trabajos ejecutados para permitir su consulta y recuperación.

## Alternativas consideradas

### Archivos JSON 

**Ventajas:**
- Sencillo de implementar
- Fácil de leer y modificar con solo un editor de texto
- No requiere dependencias externas

**Desventajas:**
- Manejar concurrencia y escrituras simultaneas es más complicado
- Consultas menos eficientes al tener muchos trabajos almacenados

### SQLite

**Ventajas:**
- Soporta transacciones
- Consultas más eficientes y directas
- Estructura organizada y dividida
- No necesita un servidor externo

**Desventajas:**
- Requiere aprender a usarla como dependencia adicional
- Es necesario decidir desde el inicio su estructura
- Es más complejo de implementar

## Decisión

**Pendiente**

## Consecuencias

### Alternativas consideradas

#### JSON

**Positivas**

- Reducción de tiempo y esfuerzo inicial del desarrollo
- Facilita que el equipo pueda inspeccionar directamente los datos almacenados durante las etapas de desarrollo y pruebas

**Negativas**

- Conforme aumente la cantidad de trabajos, el manejo y consulta de la información puede requerir mayor procesamiento
- Mayor implementación para controlar correctamente la escrituras simultáneas

**Riesgos**

- Perdida o corrupción de información si ocurre una interrupción durante una escritura u ocurre doble escritura.
- Problemas al manejar accesos simultáneos al archivo.

#### SQLite

**Positivas**

- Facilita el manejo de los registros y las consultas conforme aumente la cantidad de trabajos almacenados
- Se adapta mejor a los requisitos de consistencia, recuperación y consulta del proyecto

**Negativas**

- La implementación inicial será más compleja
- El equipo deberá de reservar tiempo para aprender y definir la estructura de la base de datos 

**Riesgos**

- Una estructura de base de datos mal diseñada podría dificultar camios posteriores
- Errores en las operaciones de escritura podrían afectar la información almacenada

## Requisitos afectados

### Alternativas consideradas

#### JSON
- +RF-08 : Consulta los metadatos de un trabajo mediante su ID
- -RF-09 : Para filtrar los trabajos sería necesario recorrer todos los registros
- +RF-12 : Conserva los metadatados y resultados en un archivo despues de reiniciar
- -RF-13 : La recuperación del historial y de trabajos interrumpidos require lógica adicional

- -RNF-05 : Las consultas pueden volverse menos eficientes conforme aumente la cantidad de registros
- +RNF-06 : Puede alamacenar los 500 registros requeridos
- -RNF-11 : Añadir mecanismos para evitar que una interrupción deje el archivo parcialmente actualizado
- -RNF-28 : Posible dificultad de recuperación ante interrupciones
- -RNF-31 : Requiere mayor lógica la recuperación y clasificación de los trabajos 


#### SQLite
- +RF-08 : Consulta los metadatos de un trabajo mediante su ID
- +RF-09 : Filtra directamente los trabajos mediante consultas a la base de datos
- +RF-12 : Conserva los metadatados y resultados en un archivo despues de reiniciar
- +RF-13 : Facilita recuperar el historial y consultar los trabajos que quedaron interrumpidos

- +RNF-05 : Las consultas de estado son más eficientes para los 100 registros requeridos
- +RNF-06 : Puede alamacenar los 500 registros requerido
- +RNF-11 : Las transacciones ayudan a evitar que una actualización quede parcialmente actualizada
- +RNF-28 : Las transacciones permiten realizar actualizaciones recuperales 
- +RNF-31 : Facilita consultar y distinguir los diferentes estados durante la recuperacion
