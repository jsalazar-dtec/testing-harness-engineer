# Tests y cobertura

**Escribe primero el caso de aceptacion y confirma que falla.**
Por que: un test que nunca estuvo en rojo no prueba que el codigo funcione — prueba que el test no comprueba nada.
Se comprueba: leyendo el diff.
Fuente: https://abseil.io/resources/swe-book/html/ch11.html

**Prueba comportamiento observable, no la implementacion.**
Por que: un test que se rompe al refactorizar sin que cambie el comportamiento no protege nada y convierte cada mejora en trabajo extra, asi que el equipo deja de refactorizar.
Se comprueba: leyendo el diff.
Fuente: https://abseil.io/resources/swe-book/html/ch12.html

**Cubre las ramas de error, no solo el camino feliz.**
Por que: el camino feliz es el que se prueba a mano todos los dias; el que nadie ejecuta hasta que falla en produccion es el otro.
Se comprueba: en el CI (coverage).
Fuente: https://abseil.io/resources/swe-book/html/ch11.html

**Prefiere muchos tests pequenos y pocos de punta a punta.**
Por que: un test grande tarda, es inestable, y cuando falla no dice donde esta el problema; su costo lo paga cada corrida de todo el equipo.
Se comprueba: leyendo el diff.
Fuente: https://testing.googleblog.com/2015/04/just-say-no-to-more-end-to-end-tests.html

**Gana la cobertura con aserciones, no con ejecucion.**
Por que: un test que recorre el codigo sin asertar nada sube el numero y no detecta un solo defecto; el umbral vive en .agent/config.json y enganarlo solo se engana el equipo a si mismo.
Se comprueba: en el CI (coverage).
Fuente: https://testing.googleblog.com/2020/08/code-coverage-best-practices.html

**Que el nombre del test diga el comportamiento que verifica.**
Por que: un test que pasa por una razon distinta a su nombre es peor que no tenerlo, porque da una garantia que nadie va a volver a revisar.
Se comprueba: leyendo el diff.
Fuente: https://abseil.io/resources/swe-book/html/ch12.html
