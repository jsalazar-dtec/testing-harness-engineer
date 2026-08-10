# Contratos de API

**Versiona la API desde el primer release publico.**
Por que: sin version, un cambio compatible y un rompimiento se ven iguales para el cliente y el segundo desestabiliza integraciones que no vieron la primera respuesta; con version, el consumidor decide cuando migrar.
Se comprueba: leyendo el diff.
Fuente: https://cloud.google.com/apis/design/versioning

**Un cambio rompedor sube la version, no muta la actual.**
Por que: renombrar un campo, cambiar el tipo de una respuesta o quitar un endpoint en v1 rompe a todo consumidor sin ninguna alerta; si lo necesitas, es v2, y v1 sigue existiendo hasta la deprecacion anunciada.
Se comprueba: leyendo el diff.
Fuente: https://semver.org/

**Anade campos como opcionales por defecto.**
Por que: hacer un campo requerido en una version existente rompe cualquier cliente que ya validaba el schema; empezar opcional deja migrar en dos releases (introducir, exigir).
Se comprueba: leyendo el diff.
Fuente: https://cloud.google.com/apis/design/compatibility

**Nunca cambies el significado de un campo existente.**
Por que: si "status" pasaba de string a enum, o de "active" a "ok", los clientes que hacian match exacto empiezan a fallar en silencio — no lanza ningun error; se procesa mal. Es peor que romper: rompe sin ruido.
Se comprueba: leyendo el diff.
Fuente: https://cloud.google.com/apis/design/compatibility

**Documenta y respeta un periodo de deprecacion antes de eliminar.**
Por que: retirar un endpoint sin anunciar equivale a apagar un servicio del que otros dependen; con anuncio y ventana, la migracion es trabajo distribuido en lugar de un incidente.
Se comprueba: no se comprueba automaticamente.
Fuente: https://cloud.google.com/apis/design/deprecation

**Devuelve errores con codigo, tipo, mensaje humano y — si aplica — retry-after.**
Por que: un cliente que solo recibe "400" no puede distinguir un input invalido de una violacion de negocio, y termina reintentando lo que nunca va a funcionar; un tipo/codigo permite manejarlo distinto.
Se comprueba: leyendo el diff.
Fuente: https://www.rfc-editor.org/rfc/rfc7807

**El schema es parte del contrato: publicalo (OpenAPI, GraphQL SDL, .proto) y validalo en CI.**
Por que: sin schema publicado, cada consumidor infiere el contrato de la respuesta que llego un dia y se rompe silenciosamente al segundo; validado en CI, un cambio incompatible no llega a la rama de integracion.
Se comprueba: en el CI (dependencias).
Fuente: https://spec.openapis.org/oas/latest.html

**No expongas ids autoincrementales de la BD como parte del contrato publico.**
Por que: revelan el volumen del negocio a competidores y facilitan enumerar recursos ajenos si la autorizacion tiene un hueco; un uuid u opaque id oculta las dos cosas.
Se comprueba: leyendo el diff.
Fuente: https://owasp.org/Top10/2025/A01_2025-Broken_Access_Control/
