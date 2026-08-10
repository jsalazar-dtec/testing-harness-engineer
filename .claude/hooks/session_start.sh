#!/usr/bin/env bash
# SessionStart: imprime que rol le toca a esta sesion y con que artefactos, para
# que Claude Code no tenga que preguntarlo. Se ejecuta al iniciar y al retomar
# una conversacion, y su salida entra al contexto como un system-reminder.
#
# Nunca bloquea. Falla abierto: si pipeline.sh no puede correr, la sesion sigue
# sin orientacion pero sigue.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

# La salida de este hook la lee Claude Code, no el usuario. Cualquier ruido en
# stderr aparece igual en el transcripto, asi que las notas informativas salen
# igual por stderr — el hook no bloquea, asi que stderr no cambia la decision.
note() { printf 'harness: %s\n' "$1" >&2; }

# Sin git, sin .agent, o sin pipeline.sh no hay orientacion que dar. Salir 0
# para que la sesion arranque igual — este hook es un lujo, no un guardrail.
[ -d "$ROOT/.agent" ] || exit 0
[ -x "$ROOT/scripts/pipeline.sh" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Se corre pipeline.sh next; su salida es el contexto de arranque. stderr se
# preserva porque contiene los mensajes de bloqueo (verified sin atestacion,
# dependencia desconocida) que son exactamente lo que la sesion necesita saber.
if ! salida="$("$ROOT/scripts/pipeline.sh" next 2>&1)"; then
  printf 'harness: al arrancar, pipeline.sh next no pudo decidir un rol:\n%s\n' "$salida" >&2
  exit 0
fi

printf 'harness: rol al arrancar esta sesion (segun pipeline.sh next):\n%s\n' "$salida" >&2
exit 0
