## Estándar de codificación
##### Hola compañeres, favor de seguir estas reglas para que todos tengamos el mismo formato de código y sea más ameno leer, entender, y factorizar codigo ajeno

###### En Rust para debian, al parecer existen por default (al instalar rust claro) unas herramientas que nos ayudan a formatear codigo, no nos complicare la vida y usaremos esos estandares de formato

### Formato General
Antes de hacer cualquier push o prueba no local, hay que ejecutar, en el siguiente orden:
- *cargo fmt* &nbsp; &nbsp; &nbsp; &nbsp; Esto le aplica formato al codigo, y así todos mantenemos un estándar
- (Alternativamente *cargo fmt --check* les dice si siguen el formato sin cambiar nada)
- *cargo clippy -- -D warnings*&nbsp; &nbsp; &nbsp; &nbsp;Esto revisa al codigo por errores basicos, y detiene la compilación en caso de warnings (Ya ustedes decidiran si el warning es sustancial o lo pueden ignorar)

(En caso de que su instalación no tuviera estas herramientas, se intala con: *rustup component add clippy rustfmt* )

### Naming Conventions
Usaremos el Naming Style conocido como **snake_case** (porque al parecer, este es el unico que soporta Rust (?), para aclarar, estos seran los formatos:

-Variable: todo_minusculas_separado_por_guion_bajo, &nbsp; varible_2, &nbsp; otro_ejemplo, &nbsp; acronimo_html, &nbsp; acronimo_fbi, &nbsp; temp, &nbsp; i

-Funciones: igual_que_las_variables(), &nbsp; funcion_2(), &nbsp; recibir_evento()

-Nombres de archivos: main.rs, &nbsp; failsafe.rs, &nbsp; database_conection.rs

-Clases/Objetos/Structs (Aquí se usa **PascalCase**): EmpiezaPorMayusculaSinSepararPalabras, &nbsp; CadaPalabraNuevaConMayuscula, &nbsp; MiClase, &nbsp; Struct1

-Constantes y Estaticos (Aquí se usa **SCREAMING_SNAKE**): TODO_EN_MAYUSCULAS_SEPARADO_POR_GUION_BAJO,&nbsp; MAX_REINTENTOS

Se que es algo confuso, pero al parecer Rust nos va a dar problemas si no utilizamos este formato

### Manejo de errores
En Rust no existen los bloques `try/catch` ni las excepciones. Manejamos los posibles fallos mediante el tipo `Result` (`Ok` / `Err`):

- **Control explícito con `match`:**
  ```rust
  match operacion_riesgosa() {
      Ok(resultado) => println!("Éxito: {resultado}"),
      Err(e) => println!("Error atrapado: {e}"),
  }
- **Manejo con valores de respaldo (unwrap_or_else):**
  
Si una función falla y queremos asignar un valor seguro por defecto sin romper la ejecución:

  ```rust
  let resultado = "no_es_un_numero".parse::<i32>()
    .unwrap_or_else(|err| {
        println!("Falló por: {err}. Usando valor por defecto.");
        0
    });
  ```

### Documentación y Comentarios
No les voy a decir como comentar su codigo, pero haganlo de manera que una persona que no sabe que estan programando pueda saber
que hace x función, o a que se refiere cierta constante o variable, etc. *Lo que si hay que evitar son los comentarios redundantes.*
Por ejemplo:

let event; // esta variable es un evento

fn printUserName(user){...} // esta función muestra el nombre de usuario

**ESO NO LO HAGAN**

*Ejemplos de comentarios utiles:*

// ATENCIÓN: No cambiar el orden de estas llamadas. 

// La función 'conectarDB()' debe inicializarse antes de usar esta función 

// Esta función puede devolver puntero nulo.

// Esta función SIEMPRE devuelve un entero, en el peor de los casos, devuelve 0.


### Mini recomendaciones extra
En Rust no trabajamos con Clases/POO tradicional, sino con Programación Orientada a Datos (structs para datos e impl para los métodos asociados):

```rust
struct MiModulo {
    estado: u8,
}

impl MiModulo {
    fn funcion1(&mut self) {}
    fn funcion2(&self) {}
}
```

###### Esto depende un poco más de sus skills, pero apreciaria que utilizaran la metodologia de *principio de responsabilidad unica* para sus funciones
Esto para que el codigo sea más legible, limpio, y modular


##### Eso es todo amigues, favor y gracias de intentar seguir estas normativas :)
