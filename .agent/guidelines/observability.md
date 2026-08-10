# Observabilidad

**Emite logs estructurados, no texto libre.**
Por que: un log en JSON con campos separados es filtrable en un incidente y agregable en un dashboard; una linea de prosa exige regex que se rompen al primer cambio de formato.
Se comprueba: leyendo el diff.
Fuente: https://cloud.google.com/logging/docs/structured-logging

**Correlaciona por request-id que viaja de extremo a extremo.**
Por que: en microservicios, sin un id que cruce el stack un incidente exige reconstruir a mano cual peticion causo cada log; con correlacion se hace en un solo filtro.
Se comprueba: leyendo el diff.
Fuente: https://www.w3.org/TR/trace-context/

**No registres datos personales, secretos ni credenciales.**
Por que: un log es un almacen de larga duracion con permisos mas laxos que la BD; un token que aparece una vez ahi se convierte en un secreto expuesto que hay que rotar.
Se comprueba: leyendo el diff.
Fuente: https://owasp.org/Top10/2025/A09_2025-Security_Logging_and_Alerting_Failures/

**Distingue niveles: error para lo que exige accion, warn para lo que puede exigirla, info para el flujo, debug para el detalle.**
Por que: si todo es error, nada lo es — la alerta que importa se ahoga en ruido y el equipo aprende a ignorarla. El nivel es lo que decide si suena una pagina o no.
Se comprueba: leyendo el diff.
Fuente: https://sre.google/sre-book/monitoring-distributed-systems/

**Instrumenta las SLIs que definen si el servicio funciona: latencia, tasa de error, saturacion.**
Por que: sin metricas sobre estos tres ejes, un incidente se detecta por la queja del usuario en lugar de por el propio sistema; la deteccion tarde cuesta mas que la deteccion sola.
Se comprueba: no se comprueba automaticamente.
Fuente: https://sre.google/sre-book/service-level-objectives/

**No apagues alertas para bajar ruido — arregla el motivo.**
Por que: silenciar una alerta que dispara mucho equivale a quitar el detector de humo porque suena de mas; la siguiente vez que dispare sera cuando ya sea tarde. El ruido es la senal de que la alerta o el sistema estan mal calibrados.
Se comprueba: no se comprueba automaticamente.
Fuente: https://sre.google/workbook/alerting-on-slos/

**Emite metricas con cardinalidad acotada.**
Por que: una metrica con el email o el request-id como etiqueta explota el numero de series y se convierte en un DoS contra tu proveedor de metricas — mismo mecanismo que un log que registra un secreto: un dato influible convertido en clave.
Se comprueba: leyendo el diff.
Fuente: https://prometheus.io/docs/practices/naming/#labels
