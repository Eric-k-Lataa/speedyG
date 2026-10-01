# Registro de uso de IA

## Objetivo
Obtener una idea de estructura para poder comenzar a implementar la maquina de estados en Rust.

## Pregunta realizada a la IA

> "dame un ejemplo sencillo de implentacion de maquina de estados en rust"

## Resultado recibido 

``` rust
Por ejemplo, una máquina que representa una puerta:

#[derive(Debug)]
enum Estado {
    Cerrada,
    Abierta,
}

#[derive(Debug)]
enum Evento {
    Abrir,
    Cerrar,
}

impl Estado {
    fn transicion(&mut self, evento: Evento) {
        match (&self, evento) {
            (Estado::Cerrada, Evento::Abrir) => {
                *self = Estado::Abierta;
            }
            (Estado::Abierta, Evento::Cerrar) => {
                *self = Estado::Cerrada;
            }
            _ => {
                println!("Transición inválida");
            }
        }
    }
}

fn main() {
    let mut puerta = Estado::Cerrada;

    println!("Estado inicial: {:?}", puerta);

    puerta.transicion(Evento::Abrir);
    println!("Después de abrir: {:?}", puerta);

    puerta.transicion(Evento::Cerrar);
    println!("Después de cerrar: {:?}", puerta);
}

```

## Revisión realizada

Se probó el codigo generado por la IA y funcionó correctamente. Además, se buscó comprender cada parte del codigo para entender su funcionamiento y verificar que fuera una estructura adecuada para implementar la máquina de estados para nuestro proyecto.

## Decisión

**Modificado**

El ejemplo se utilizó como base para estructurar la máquina de estados del proyecto. Sin embargo, el ejemplo era demasiado simple para las necesidades del SpeedyG, por lo que se cambiaron los valores de estado y evento para adaptarlos al proyecto.
También se modificó el manejo de las trancisiones inválidas para utilizar un warn en lugar de print, se añadieron getters y la inicialización de un job. 

## Prueba agregada
Se hicieron simulaciones de eventos para comprobar el correcto cambio de estado de los Job, así como la inicialización y la generación de un warning en casos de eventos invalidos para un estado.

## Aprendizaje

Se comprendió mejor el funcionamiento de Rust gracias a este ejemplo de implementación, lo que facilitó la progrmación de la máquina de estados. Además, se comprobó que en rust se puede crear una maquina de estados de manera sencilla y facil de leer.