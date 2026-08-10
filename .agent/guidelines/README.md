# Guidelines

La vara con la que se escribe y se juzga el codigo de este proyecto.

`implementer` las lee **antes** de escribir: son piso, no sugerencia.
`reviewer` las lee **al juzgar** el diff. Una sola rubrica, dos lectores,
ninguna copia — por eso las REGLAS no se repiten dentro de ningun prompt.

## Que leer

Siempre, sea cual sea la tarea:

- `clean-code.md` — nombres, tamano, duplicacion, comentarios.
- `testing.md` — que prueba un test que vale.
- `dependencies.md` — vulnerabilidades, lockfiles, secretos, exclusiones.

Segun lo que toque la tarea:

- `security-backend.md` — autorizacion, inyeccion, criptografia, errores, SSRF.
- `security-frontend.md` — XSS y sinks del DOM, CSP, datos en el cliente.
- `api-contracts.md` — versionado, campos opcionales, deprecacion, schemas publicados.
- `observability.md` — logs estructurados, correlacion, niveles, SLIs, cardinalidad.

## Como se escribe una regla

Cuatro lineas, siempre las mismas, siempre en este orden:

    **Regla en imperativo.**
    Por que: la consecuencia concreta de no cumplirla.
    Se comprueba: leyendo el diff. | en el CI (<job>). | no se comprueba automaticamente.
    Fuente: <url>

`Se comprueba` es el campo que hace honesto a todo esto. Una regla marcada
"en el CI" le dice al reviewer que mire el run en vez de opinar. Una marcada
"no se comprueba automaticamente" le dice que ahi tiene que mirar el — y le
impide dar por cubierto lo que nadie miro. Sin ese campo las tres categorias
se confunden en una sola sensacion de "esto ya esta cubierto", que es
exactamente lo que este harness existe para evitar: saltado no es pasado.

`Fuente` impide que esto acumule opiniones anonimas. Las preferencias de
estilo ya las impone el linter.

## Como agregar criterios

1. La regla va al archivo tematico que le toca. Si no existe ninguno, se crea
   un archivo nuevo **y se agrega su linea a "Que leer"** aqui arriba. Los
   roles leen este indice: por eso un archivo nuevo les llega a los dos sin
   tocar sus prompts. Pero las vinetas de arranque de `reviewer.md` y el
   parrafo de `implementer.md` nombran los archivos actuales, no son un
   catalogo que se genere solo — si agregas uno, conviene revisarlas.
2. Se escribe con las cuatro lineas del formato. **Sin fuente citable, no
   entra.**
3. Criterio de admision: si la regla no puede enunciarse de forma que alguien
   pueda decir si se cumple o no, no es una regla — es un deseo. Se reformula
   o se descarta.
4. Si exige una herramienta que el CI no tiene, se agrega tambien al workflow
   del proyecto. Si no se agrega, la regla se marca "no se comprueba
   automaticamente" y se asume ese costo con los ojos abiertos.

Este directorio esta protegido: no se edita desde un agente. Es a proposito —
una vara que el medido puede mover no es una vara. Si una regla estorba o
esta mal, se reporta; la edita una persona.
