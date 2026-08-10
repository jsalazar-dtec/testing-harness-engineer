#!/usr/bin/env bash
# Instalacion interactiva del harness en un proyecto que copio template/.
#
# Rellena .agent/config.json y .agent/init.sh preguntando al usuario. NO invoca
# a un agente, no toca el codigo del proyecto, no ejecuta los comandos que
# configura — solo los guarda. verify.sh los va a correr en su momento; si
# aqui algo esta mal, aparece rojo entonces y no en un test que "pasa" por
# error.
#
# Idempotente: correrlo de nuevo relee lo que ya hay y solo pregunta lo vacio.
# No borra respuestas previas.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
AGENT_DIR="$ROOT/.agent"
CONFIG="$AGENT_DIR/config.json"
INIT="$AGENT_DIR/init.sh"

die()   { printf 'harness: %s\n' "$1" >&2; exit 1; }
note()  { printf 'harness: %s\n' "$1" >&2; }
ask() {
  local prompt="$1" default="${2:-}" answer
  if [ -n "$default" ]; then
    printf '%s [%s]: ' "$prompt" "$default" >&2
  else
    printf '%s: ' "$prompt" >&2
  fi
  IFS= read -r answer </dev/tty || true
  printf '%s' "${answer:-$default}"
}

command -v jq >/dev/null 2>&1 || die "falta jq — instalalo antes de correr bootstrap"

[ -f "$CONFIG" ] || die "no existe $CONFIG — copiaste template/ dentro del proyecto?"
jq -e . "$CONFIG" >/dev/null 2>&1 || die "$CONFIG no es JSON valido — arreglalo a mano antes de continuar"

schema="$(jq -r '."$schema" // ""' "$CONFIG")"
if [ "$schema" != "harness/1" ]; then
  note "\$schema en $CONFIG es '${schema:-vacio}' — este bootstrap escribe la version 'harness/1'"
fi

# git init si no existe: sin repo, task.sh attest no tiene HEAD que leer y
# todo el resto del harness pierde su fundamento.
if ! git -C "$ROOT" rev-parse --show-toplevel >/dev/null 2>&1; then
  answer="$(ask "$ROOT no es un repo git — inicializar? (s/n)" "s")"
  case "$answer" in
    s|S|si|Si|y|Y|yes|Yes)
      git -C "$ROOT" init -q
      note "repo git inicializado en $ROOT"
      ;;
    *) die "sin repo git no hay harness — corre 'git init' y vuelve a intentar" ;;
  esac
fi

# Perfil del proyecto (stack). Se pregunta una sola vez y planner/implementer
# lo leen de config.json.
stack="$(jq -r '.stack // ""' "$CONFIG")"
if [ -z "$stack" ] || [ "$stack" = "unknown" ]; then
  stack="$(ask "Lenguaje y framework (ej: typescript+nestjs, python+django, go, monorepo:react+node)" "")"
  [ -n "$stack" ] || die "stack es obligatorio — planner y implementer lo leen para dividir tareas"
fi

# Rama de integracion. null significa "trunk-based, PRs contra main".
integration="$(jq -r '.integrationBranch // ""' "$CONFIG")"
if [ -z "$integration" ] || [ "$integration" = "null" ]; then
  integration="$(ask "Rama de integracion (develop|dev|trunk|integration) o vacio para trunk-based" "")"
fi

# Los cuatro comandos que definen los gates. Vacio deja el gate como skipped.
lint_cmd="$(jq -r '.commands.lint // ""' "$CONFIG")"
if [ -z "$lint_cmd" ] || [ "$lint_cmd" = "null" ]; then
  lint_cmd="$(ask "Comando de lint (vacio = skipped)" "")"
fi
test_cmd="$(jq -r '.commands.test // ""' "$CONFIG")"
if [ -z "$test_cmd" ] || [ "$test_cmd" = "null" ]; then
  test_cmd="$(ask "Comando de test (vacio = skipped)" "")"
fi
coverage_cmd="$(jq -r '.commands.coverage // ""' "$CONFIG")"
if [ -z "$coverage_cmd" ] || [ "$coverage_cmd" = "null" ]; then
  coverage_cmd="$(ask "Comando de coverage — DEBE imprimir solo el numero, ej: pytest --cov | grep TOTAL | awk '{print \$4}' (vacio = skipped)" "")"
fi
related_cmd="$(jq -r '.commands.testRelated // ""' "$CONFIG")"
if [ -z "$related_cmd" ] || [ "$related_cmd" = "null" ]; then
  related_cmd="$(ask 'Comando de tests relacionados al archivo tocado (usa la env $HARNESS_FILE, vacio = skipped)' "")"
fi

# Escritura atomica del config.json — el mismo patron que verify.sh y task.sh.
tmp="$(mktemp)"
jq --arg s "$stack" \
   --arg ib "$integration" \
   --arg lint "$lint_cmd" \
   --arg test "$test_cmd" \
   --arg cov "$coverage_cmd" \
   --arg rel "$related_cmd" \
   '. + {"$schema": "harness/1", "stack": $s,
         "integrationBranch": (if $ib == "" then null else $ib end),
         "commands": {
           "lint":        (if $lint == "" then null else $lint end),
           "test":        (if $test == "" then null else $test end),
           "coverage":    (if $cov  == "" then null else $cov  end),
           "testRelated": (if $rel  == "" then null else $rel  end)
         }}' "$CONFIG" > "$tmp" \
  || { rm -f "$tmp"; die "no se pudo componer el nuevo $CONFIG"; }
mv "$tmp" "$CONFIG"
note "config.json actualizado"

# init.sh solo se reescribe si sigue siendo el placeholder de fabrica. Si el
# proyecto ya lo edito, no lo pisamos.
if grep -q "sin configurar" "$INIT" 2>/dev/null; then
  cat > "$INIT" <<INIT
#!/usr/bin/env bash
# Como se levanta y se prueba este proyecto ($stack).
# Rellena los comandos concretos aqui — este script lo consulta doctor.sh y
# lo puede correr un agente para verificar que el entorno funciona.
set -euo pipefail

# Ejemplo (borra y adapta):
#   npm install
#   npm run migrate

printf 'harness: init.sh sin comandos concretos todavia — anade las lineas de arriba\n' >&2
exit 0
INIT
  chmod +x "$INIT"
  note "init.sh escrito con esqueleto para $stack — completa los comandos concretos"
fi

# CI: no lo escribimos, solo recordamos que reviewer lo va a buscar por nombre.
note "reviewer va a buscar jobs de GitHub Actions con los nombres exactos: tests, coverage, dependencias, secretos"
note "si no tienes ese workflow, es trabajo previo — reviewer va a rechazar sin CI verde"

printf 'harness: bootstrap completo — corre scripts/doctor.sh para verificar el entorno\n' >&2
