# Dependencias y cadena de suministro

Las fallas de cadena de suministro son el numero 3 del OWASP Top 10 2025.
Lo que se agrega aqui es superficie de ataque que nadie de este equipo escribio.

**No agregues una dependencia con vulnerabilidad conocida.**
Por que: entra a produccion con el CVE puesto, y el dia que se explote el costo no lo paga quien la agrego.
Se comprueba: en el CI (dependencias).
Fuente: https://owasp.org/Top10/2025/A03_2025-Software_Supply_Chain_Failures/

**Justifica cada exclusion con id, motivo y url del advisory.**
Por que: una exclusion sin las tres cosas es indistinguible de haber silenciado el escaner, y nadie va a poder revisarla despues. Los archivos osv-scanner.toml, .trivyignore, .semgrepignore y .gitleaksignore lo piden en su encabezado.
Se comprueba: leyendo el diff.
Fuente: https://google.github.io/osv-scanner/configuration/

**Fija las versiones con lockfile y commitealo con el cambio.**
Por que: sin lockfile en el mismo commit, lo que se probo y lo que se instala son dos arboles distintos, y la diferencia aparece en produccion.
Se comprueba: leyendo el diff.
Fuente: https://slsa.dev/spec/v1.0/threats

**Justifica en tu reporte cada dependencia nueva.**
Por que: cada una amplia la superficie de la cadena de suministro y agrega un mantenedor en el que hay que confiar; si lo que resuelve ya esta resuelto, ese costo no compra nada.
Se comprueba: no se comprueba automaticamente.
Fuente: https://scorecard.dev/

**No pongas secretos en el codigo, en los logs ni en argv.**
Por que: el codigo se clona, los logs se agregan y argv lo lee cualquier proceso local; un secreto que llego ahi ya esta comprometido y rotarlo es el unico arreglo.
Se comprueba: en el CI (secretos).
Fuente: https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html
