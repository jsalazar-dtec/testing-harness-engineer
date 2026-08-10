#!/usr/bin/env bash
# PostToolUse tras Edit y Write: lint + tests relacionados al archivo tocado.
# Nunca bloquea. Su trabajo es acortar el ciclo de feedback, no imponer nada:
# imponer es trabajo de verify.sh.
set -uo pipefail

report() { printf 'harness: %s\n' "$1" >&2; }

command -v jq >/dev/null 2>&1 || exit 0

payload="$(cat)"
path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
[ -n "$path" ] || exit 0

config="${AGENT_DIR:-.agent}/config.json"
[ -f "$config" ] || exit 0

# Un config roto y un gate sin configurar decian los dos "skipped", asi que un
# archivo con un error de sintaxis degradaba a "nada que hacer" sin ninguna senal.
jq -e . "$config" >/dev/null 2>&1 || {
  report "config.json invalido — revisa la sintaxis; el loop local no corre nada"
  exit 0
}

# macOS no trae timeout; coreutils lo instala como gtimeout. Sin ninguno de los dos
# se corre sin limite y se avisa: PostToolUse es SINCRONICO, asi que un lint que
# cuelga cuelga la sesion, y eso viola el "nunca bloquea" de este hook.
TIMEOUT_BIN=""
for candidate in timeout gtimeout; do
  if command -v "$candidate" >/dev/null 2>&1; then
    TIMEOUT_BIN="$candidate"
    break
  fi
done

run_step() {
  local label="$1" cmd="$2" rc=0
  if [ -z "$cmd" ] || [ "$cmd" = "null" ]; then
    report "$label: skipped"
    return 0
  fi
  if [ -n "$TIMEOUT_BIN" ]; then
    "$TIMEOUT_BIN" "${HARNESS_STEP_TIMEOUT:-60}" bash -c "$cmd" 2>/dev/null
  else
    bash -c "$cmd" 2>/dev/null
  fi
  rc=$?
  case "$rc" in
    0)   report "$label: ok" ;;
    124) report "$label: timeout a los ${HARNESS_STEP_TIMEOUT:-60}s — corre '$cmd' a mano" ;;
    *)   report "$label: fallo — corre '$cmd' para ver el detalle" ;;
  esac
}

lint="$(jq -r '.commands.lint // ""' "$config" 2>/dev/null)"
related="$(jq -r '.commands.testRelated // ""' "$config" 2>/dev/null)"

# La ruta viaja por el ENTORNO, nunca interpolada en el texto del comando.
# Interpolarla y pasar el resultado a bash -c era inyeccion de comandos: un
# file_path como 'src/a.ts; touch PWNED' ejecutaba el touch, y este hook corre
# en cada edicion. Dentro de una variable, ; y los backticks son caracteres y
# no sintaxis, asi que el mismo nombre de archivo deja de ejecutar nada.
export HARNESS_FILE="$path"

if [ -z "$TIMEOUT_BIN" ] && { [ -n "$lint" ] || [ -n "$related" ]; }; then
  report "sin timeout disponible — instala coreutils (gtimeout) si un lint o un test puede colgarse"
fi

run_step "lint" "$lint"
run_step "tests relacionados" "$related"

exit 0
