# Seguridad — frontend

**No inyectes HTML crudo desde datos.**
Por que: innerHTML, dangerouslySetInnerHTML y v-html ejecutan lo que reciben; la api de texto del framework escapa por defecto y cierra el caso entero.
Se comprueba: leyendo el diff.
Fuente: https://cheatsheetseries.owasp.org/cheatsheets/DOM_based_XSS_Prevention_Cheat_Sheet.html

**Si hay que inyectar HTML, sanitiza con una biblioteca mantenida.**
Por que: una expresion regular propia siempre pierde contra un caso que no se te ocurrio, y el catalogo de esos casos es un trabajo de tiempo completo que ya hace otro.
Se comprueba: leyendo el diff.
Fuente: https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html

**Escapa segun el destino: HTML, atributo, url y contexto JS tienen reglas distintas.**
Por que: escapar "en general" no existe, y lo que es seguro dentro de un texto deja de serlo dentro de un atributo o de una url.
Se comprueba: leyendo el diff.
Fuente: https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html

**No uses eval, new Function ni setTimeout con string.**
Por que: convierten cualquier dato que llegue ahi en codigo, y no hay escapado que lo arregle despues.
Se comprueba: leyendo el diff.
Fuente: https://developer.mozilla.org/en-US/docs/Web/Security

**Trata CSP y Trusted Types como red de seguridad, no como reemplazo del escapado.**
Por que: una politica cubre lo que se te escapo, pero un solo sink sin proteger la atraviesa; el orden es escapar primero y endurecer despues.
Se comprueba: no se comprueba automaticamente.
Fuente: https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy

**No guardes en el cliente lo que no debe estar ahi.**
Por que: localStorage lo lee cualquier script que corra en la pagina, y todo lo que se empaqueta en el bundle es publico por definicion — un secreto en el frontend ya esta publicado.
Se comprueba: leyendo el diff.
Fuente: https://cheatsheetseries.owasp.org/cheatsheets/HTML5_Security_Cheat_Sheet.html

**Vuelve a aplicar en el servidor toda validacion del cliente.**
Por que: la del cliente es de usabilidad; el atacante no usa tu formulario.
Se comprueba: leyendo el diff.
Fuente: https://cheatsheetseries.owasp.org/cheatsheets/Input_Validation_Cheat_Sheet.html

**Protege los destinos externos y el enmarcado.**
Por que: sin rel noopener la pagina destino puede redirigir la tuya, y sin proteccion de enmarcado un iframe ajeno cosecha los clics de tu usuario.
Se comprueba: leyendo el diff.
Fuente: https://cheatsheetseries.owasp.org/cheatsheets/Clickjacking_Defense_Cheat_Sheet.html
