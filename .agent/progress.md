# Bitacora del proyecto

El estado del trabajo vive en dos archivos, cada uno con un rol:

- `tasks.json` — la verdad presente: que tarea existe, en que estado esta, con que rama y PR.
- `history.jsonl` — la verdad pasada: append-only, una linea JSON por evento (`start`, `implemented`, `review`, `verified`, `merged`).

Este archivo (`progress.md`) es solo un puntero. **No escribas prosa aqui**: para eventos usa `history.jsonl`, para decisiones no obvias usa un ADR en `docs/` — cada uno tiene lector y forma distinta, y mezclarlos garantiza que ninguno se lea.

## Como se lee la historia

```bash
# Todos los eventos de una tarea, en orden:
jq -c 'select(.task == "T3")' .agent/history.jsonl

# Ultima transicion de cada tarea:
jq -s 'group_by(.task) | map(max_by(.ts))' .agent/history.jsonl

# Cuantas veces re-revisaron cada tarea:
jq -c 'select(.event == "review")' .agent/history.jsonl | jq -s 'group_by(.task) | map({task: .[0].task, n: length})'
```

## Como se escribe

Cada `task.sh <subcomando>` que muta estado (`start`, `implemented`, `review`, `verify`, `merged`) anade su propia linea. Nadie escribe a mano: si tu evento no aparece, el subcomando que lo produce esta mal, no la bitacora.

Formato de linea (JSON compacto, un objeto por linea, sin comas entre lineas):

```json
{"ts": "2026-08-10T12:34:56Z", "event": "verified", "task": "T3", "actor": "task.sh", "detail": {"configHash": "..."}}
```

Los campos `ts`, `event`, `task` y `actor` son obligatorios. `detail` es un objeto libre que cada evento rellena a su manera.
