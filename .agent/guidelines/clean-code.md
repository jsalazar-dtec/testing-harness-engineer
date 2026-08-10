# Codigo limpio

**Da una sola responsabilidad a cada unidad.**
Por que: un archivo que crece deja de caber en la cabeza de quien lo lee y en el contexto de quien lo edita, y cada cambio arrastra riesgo que no le corresponde.
Se comprueba: leyendo el diff.
Fuente: https://google.github.io/eng-practices/review/reviewer/looking-for.html

**Nombra por lo que hace, no por como lo hace.**
Por que: un nombre que describe la implementacion miente en cuanto la implementacion cambia, y nadie renombra al refactorizar.
Se comprueba: leyendo el diff.
Fuente: https://github.com/ryanmcdermott/clean-code-javascript#variables

**No dupliques bloques de logica.**
Por que: dos copias divergen, y el bug se arregla en una sola. La duplicacion literal es el unico caso sin discusion posible.
Se comprueba: leyendo el diff.
Fuente: https://refactoring.guru/smells/duplicate-code

**Manten corta la lista de parametros.**
Por que: mas de tres o cuatro parametros es la senal de que falta una estructura, y multiplica las combinaciones que hay que probar.
Se comprueba: leyendo el diff.
Fuente: https://refactoring.guru/smells/long-parameter-list

**No dejes codigo muerto ni ramas inalcanzables.**
Por que: el lector no puede distinguir lo que no se usa de lo que no entendio, asi que lo mantiene por las dudas para siempre.
Se comprueba: leyendo el diff.
Fuente: https://refactoring.guru/smells/dead-code

**Escribe comentarios que expliquen por que, no que.**
Por que: un comentario que repite la linea de abajo se desactualiza en el primer cambio y entonces miente; el razonamiento que no esta en el codigo es lo unico que no se puede recuperar leyendolo.
Se comprueba: leyendo el diff.
Fuente: https://github.com/ryanmcdermott/clean-code-javascript#comments

**Mejora solo lo que ya estas tocando.**
Por que: un diff que arregla cosas fuera de la tarea no se puede revisar ni revertir por partes, y esconde el cambio que importaba.
Se comprueba: leyendo el diff.
Fuente: https://google.github.io/eng-practices/review/developer/small-cls.html

**Deja limpia la salida de la suite.**
Por que: un warning nuevo entrena a todos a ignorar la salida, y el dia que aparezca uno real nadie lo va a ver.
Se comprueba: en el CI (tests).
Fuente: https://google.github.io/eng-practices/review/reviewer/looking-for.html
