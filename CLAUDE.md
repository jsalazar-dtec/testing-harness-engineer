# Como arrancar cualquier sesion en este repo

Este archivo lo lee Claude Code al iniciar. La orquestacion del trabajo la
decide `scripts/pipeline.sh next` a partir del estado en `.agent/`: no la
adivines, preguntala.

## Primer paso, siempre

```
./scripts/pipeline.sh next
```

Lee la respuesta. Trae `role=<X>` y los artefactos que ese rol necesita —
spec, brief, guidelines, task, branch. **No invoques ningun rol sin haber
pasado por esa respuesta.** Un rol invocado a mano recibe un contexto que el
harness no controla, y ahi es donde se cuelan las regresiones que este repo
existe para impedir.

## Como se elige rol

`pipeline.sh next` aplica esta prioridad, en orden:

1. `verified` sin atestacion en `git` — alto duro, nada mas avanza hasta arreglarlo.
2. Tareas `implemented`: `reviewer` (tecnico) -> `business-reviewer` (negocio) -> `verifier`.
3. Tareas `pending` desbloqueadas: `integrator` para abrir rama, luego `implementer`.
4. Un borrador `*-issue-*-DRAFT.md` esperando triage: `intake-reviewer`.
5. Sin spec: `spec`.
6. Con spec y sin tareas: `planner`.

Ninguno de estos pasos lo decide la sesion. Todos salen del estado del repo.

## Los ocho roles y su contrato

| Rol | Escribe | Bash | Que hace |
|---|---|---|---|
| `spec` | `.agent/specs/`, `.agent/acceptance/` | no | Define QUE se construye y sus contratos. |
| `planner` | `.agent/tasks.json` | no | Decompone el spec en tareas atomicas. |
| `intake-reviewer` | no | solo lectura | Juzga si un Issue trae lo necesario para entrar. |
| `implementer` | codigo + `tasks.json` (a `implemented`) | si | Escribe UNA tarea con TDD. |
| `reviewer` | no | solo lectura | Gate tecnico: clean code, seguridad, bugs. |
| `business-reviewer` | no | solo lectura | Gate de negocio contra spec y `.agent/acceptance/`. |
| `verifier` | via `task.sh` | si | Corre los gates y promueve a `verified`. |
| `integrator` | ramas, PRs | si | Abre rama, abre PR, back-merge. **No mergea.** |

Los tres roles de revision son deliberadamente sin `Write`: no pueden dejar en
disco su propio rastro de "ya revise esto". Su veredicto lo registra la
sesion orquestadora con `task.sh review` o `task.sh intake` — nunca el rol
que lo emitio.

## Lo que la sesion orquestadora NO puede hacer

- **No promuevas tareas a mano** — `verified` y `merged` solo salen de
  `task.sh verify` y `task.sh merged`, que corren los gates y exigen sello.
  Un `jq` directo sobre `tasks.json` lo bloquea `protect_artifacts.sh` con
  exit 2.
- **No edites `.agent/guidelines/`, `.agent/config.json`, ni ningun script del
  harness** desde una sesion de agente. Son la vara, no lo medido; la mueve
  una persona fuera del ciclo.
- **No mergees.** Ni `gh pr merge`, ni `git push --force` a rama protegida.
  El diff del PR es la ultima defensa contra una atestacion forjada.

## Ejecutar los gates

- Iteracion rapida por edicion: la corre `.claude/hooks/cheap_loop.sh`
  (lint + tests relacionados al archivo tocado). Nunca bloquea.
- Iteracion completa antes de promover: `./scripts/task.sh verify <id>`.
  Corre lint, tests, coverage y (si estan configurados) Sonar y Actions.
- Comprobar que un `verified` sigue en pie: `./scripts/task.sh attest <id>`.

## Cuando algo no encaja

Si un requisito de la tarea contradice el spec, o un contrato, o algo que
encuentres en el codigo: **detente y reportalo.** No elijas cual descartar.
La cadena reviewer -> business-reviewer -> verifier existe justo para eso.

## Referencia

- `README.md` en la raiz del repo — la vision completa.
- `.agent/guidelines/README.md` — la rubrica con la que se juzga tu trabajo.
- `docs/superpowers/specs/` — el diseno detras de cada pieza (si existe).
