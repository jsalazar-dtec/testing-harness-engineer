# Seguridad — backend

**Autoriza por objeto, no solo por ruta.**
Por que: que el usuario este autenticado no dice nada sobre si ese recurso es suyo; es el numero 1 del Top 10 2025 y el numero 1 del API Top 10 porque cambiar un id en la url es todo lo que hace falta.
Se comprueba: leyendo el diff.
Fuente: https://owasp.org/Top10/2025/A01_2025-Broken_Access_Control/

**Valida toda entrada externa en el borde, con lista de lo permitido.**
Por que: una lista de lo prohibido siempre esta incompleta, y validar en el fondo significa que el dato ya viajo por medio sistema antes de que alguien lo mirara.
Se comprueba: leyendo el diff.
Fuente: https://cheatsheetseries.owasp.org/cheatsheets/Input_Validation_Cheat_Sheet.html

**Usa consultas parametrizadas, nunca concatenacion.**
Por que: concatenar deja que el dato decida la estructura de la consulta, que es literalmente lo que es una inyeccion; parametrizar lo cierra por construccion y no por vigilancia.
Se comprueba: leyendo el diff.
Fuente: https://cheatsheetseries.owasp.org/cheatsheets/Query_Parameterization_Cheat_Sheet.html

**No dejes que texto influible llegue a un shell, a eval, a una ruta o a un filtro.**
Por que: es la misma inyeccion con otro interprete, y ahi no hay ORM que te cubra — el argumento va por --arg o por la api que separa datos de codigo.
Se comprueba: leyendo el diff.
Fuente: https://owasp.org/Top10/2025/A05_2025-Injection/

**Devuelve errores sin internals.**
Por que: un stack trace, un nombre de tabla o una ruta del servidor en la respuesta le dan al atacante el mapa que iba a tardar horas en levantar. El manejo de excepciones entro al Top 10 2025 como A10.
Se comprueba: leyendo el diff.
Fuente: https://owasp.org/Top10/2025/A10_2025-Mishandling_of_Exceptional_Conditions/

**No escribas criptografia a mano.**
Por que: los modos, los nonces y las comparaciones en tiempo constante son donde falla, y ninguna de las tres cosas se ve rota mirando el codigo; usa la biblioteca estandar con sus defaults.
Se comprueba: leyendo el diff.
Fuente: https://owasp.org/Top10/2025/A04_2025-Cryptographic_Failures/

**Controla el destino de toda peticion saliente.**
Por que: una url que viene del usuario convierte a tu servidor en un pivote hacia la red interna y hacia los metadatos del proveedor cloud; sin allowlist no hay defensa.
Se comprueba: leyendo el diff.
Fuente: https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html

**Registra los eventos de seguridad y no registres datos personales ni credenciales.**
Por que: un log que no sirve en un incidente y un log que filtra datos son el mismo defecto en direcciones opuestas, y los dos se descubren tarde.
Se comprueba: leyendo el diff.
Fuente: https://owasp.org/Top10/2025/A09_2025-Security_Logging_and_Alerting_Failures/

**Pon limites explicitos donde el consumo no esta acotado.**
Por que: sin tamano maximo de payload, paginacion y rate limiting, un solo cliente tumba el servicio sin necesitar ninguna vulnerabilidad.
Se comprueba: no se comprueba automaticamente.
Fuente: https://owasp.org/API-Security/editions/2023/en/0xa4-unrestricted-resource-consumption/
