#!/usr/bin/env bash
# Cadena de gates del proyecto. Emite JSON por stdout y notas por stderr.
# Exit: 0 todo verde o saltado, 3 algún gate rojo, 1 entorno incompleto.
#
# Un gate que no corrió se reporta skipped, nunca pass. Confundirlos es
# exactamente cómo se cuela código sin verificar.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/common.sh
. "$HERE/lib/common.sh"

require_cmd jq

AGENT_DIR="${AGENT_DIR:-.agent}"

# AGENT_DIR elige que config.json se lee, y con eso elige QUE GATES CORREN. Medido: con
# el config.json real en rojo, `AGENT_DIR=/tmp/falso scripts/task.sh verify T1` corria
# contra un config permisivo y producia un reporte GENUINO —sha real, overall pass,
# dirty false— para el HEAD real. Ese reporte se commitea y attest dice 0 mientras este
# script sigue saliendo 3. Leer el reporte de git no lo detecta: esta trackeado y es
# identico byte a byte a uno legitimo. La configuracion del harness vive en el repo.
_harness_top="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -n "$_harness_top" ]; then
  _harness_agent_phys="$(cd "$AGENT_DIR" 2>/dev/null && pwd -P)"
  # Un AGENT_DIR que no existe se deja al chequeo de $CONFIG, que da un mensaje mejor.
  if [ -n "${_harness_agent_phys:-}" ]; then
    case "$_harness_agent_phys" in
      "$_harness_top"|"$_harness_top"/*) ;;
      *) die "AGENT_DIR ($AGENT_DIR) no esta dentro del arbol de trabajo ($_harness_top) — la configuracion de los gates vive en el repo" ;;
    esac
  fi
fi

CONFIG="$AGENT_DIR/config.json"
[ -f "$CONFIG" ] || die "no existe $CONFIG — corre bootstrap.sh en este proyecto"
[ ! -L "$CONFIG" ] || die "$CONFIG es un symlink — la configuracion tiene que ser un archivo del repo"
# Un config.json corrupto no es "sin configurar": es entorno incompleto. Sin este
# chequeo cada cfg() devolvia vacio, todos los gates quedaban skipped y overall
# salia pass, asi que un config.json roto aprobaba la tarea.
jq -e . "$CONFIG" >/dev/null 2>&1 \
  || die "$CONFIG no es JSON valido — arreglalo antes de verificar nada"

note() { printf 'harness: %s\n' "$1" >&2; }

cfg() { jq -r "$1 // \"\"" "$CONFIG" 2>/dev/null; }

# macOS no trae timeout; coreutils lo instala como gtimeout. Sin ninguno de los dos se
# corre sin limite y se avisa. cheap_loop.sh gano su timeout en la Task 9 y verify.sh
# nunca lo tuvo: un test o un lint que cuelga cuelga la verificacion entera.
TIMEOUT_BIN=""
for candidate in timeout gtimeout; do
  if command -v "$candidate" >/dev/null 2>&1; then
    TIMEOUT_BIN="$candidate"
    break
  fi
done
GATE_TIMEOUT="${HARNESS_GATE_TIMEOUT:-900}"
if [ -z "$TIMEOUT_BIN" ] && [ -n "$(cfg '.commands.lint')$(cfg '.commands.test')$(cfg '.commands.coverage')" ]; then
  note "sin timeout disponible — instala coreutils (gtimeout) si un gate puede colgarse"
fi

run_limited() {
  if [ -n "$TIMEOUT_BIN" ]; then
    "$TIMEOUT_BIN" "$GATE_TIMEOUT" bash -c "$1" >/dev/null 2>&1
  else
    bash -c "$1" >/dev/null 2>&1
  fi
}

# Corre un comando y devuelve pass/fail/skipped. Un gate que no corrio es skipped,
# nunca pass, y se anota por stderr: sin la nota, un operador no puede distinguir
# "no configurado" de "corrio y paso" sin leer el JSON.
gate_command() {
  local label="$1" cmd="$2"
  if [ -z "$cmd" ]; then
    note "$label: sin comando en config.json (commands.$label) — gate saltado"
    printf 'skipped'
    return 0
  fi
  if run_limited "$cmd"; then
    printf 'pass'
  else
    printf 'fail'
  fi
}

lint_status="$(gate_command lint "$(cfg '.commands.lint')")"
tests_status="$(gate_command test "$(cfg '.commands.test')")"

coverage_cmd="$(cfg '.commands.coverage')"
# El umbral va a --argjson, que exige JSON valido. Un "95%" hacia fallar TODOS los
# jq -n de la cobertura, coverage_json se quedaba vacio, su status llegaba vacio al
# bucle de overall (que solo degradaba con "fail") y el jq -n final tambien fallaba
# sin cambiar el codigo de salida: exit 0, stdout vacio, cobertura real del 24%.
threshold="$(jq -r '.coverageThreshold // 95' "$CONFIG")"
if ! printf '%s' "$threshold" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
  note "coverageThreshold debe ser un numero sin comillas ni signos (recibido: ${threshold:-vacio}) — se usa 95 por defecto"
  threshold=95
fi
if [ -z "$coverage_cmd" ]; then
  note "coverage: sin comando en config.json (commands.coverage) — gate saltado"
  coverage_json="$(jq -n --argjson t "$threshold" \
    '{value: null, threshold: $t, status: "skipped"}')"
else
  # El comando tiene que imprimir SOLO el numero. No se parsea salida decorada, y
  # esa es una decision, no una limitacion: ninguna heuristica puede distinguir en
  # texto arbitrario un numero que es el umbral de uno que es el valor, porque son
  # el mismo token. Dos intentos lo demostraron — "Statements: 12/50 (24%)" pasaba
  # un umbral del 95, y luego "Threshold: 95% actual: 24%" volvio a pasarlo. El
  # harness prefiere negarse a adivinar antes que aprobar cobertura que no midio.
  if [ -n "$TIMEOUT_BIN" ]; then
    coverage_raw="$("$TIMEOUT_BIN" "$GATE_TIMEOUT" bash -c "$coverage_cmd" 2>/dev/null \
      | head -1 | tr -d '[:space:]')"
  else
    coverage_raw="$(bash -c "$coverage_cmd" 2>/dev/null | head -1 | tr -d '[:space:]')"
  fi
  coverage_value="${coverage_raw%\%}"

  if ! printf '%s' "$coverage_value" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
    note "commands.coverage debe imprimir solo el numero (recibido: ${coverage_raw:-vacio}) — extrae el valor en config.json, por ejemplo con grep o awk"
    coverage_json="$(jq -n --argjson t "$threshold" \
      '{value: null, threshold: $t, status: "fail"}')"
  elif awk -v v="$coverage_value" -v t="$threshold" 'BEGIN { exit !(v >= t) }'; then
    coverage_json="$(jq -n --argjson v "$coverage_value" --argjson t "$threshold" \
      '{value: $v, threshold: $t, status: "pass"}')"
  else
    coverage_json="$(jq -n --argjson v "$coverage_value" --argjson t "$threshold" \
      '{value: $v, threshold: $t, status: "fail"}')"
  fi
fi

# Sonar: se salta sin host, projectKey o token. Nunca se reporta pass sin correr.
sonar_status="skipped"
sonar_host="$(cfg '.sonar.host')"
sonar_key="$(cfg '.sonar.projectKey')"
if [ -z "$sonar_host" ] || [ -z "$sonar_key" ]; then
  note "sonar: sin host o projectKey en config.json — gate saltado"
elif [ -z "${SONAR_TOKEN:-}" ]; then
  note "sonar: falta SONAR_TOKEN en el entorno — gate saltado"
elif ! command -v curl >/dev/null 2>&1; then
  note "sonar: falta curl — gate saltado"
else
  # El token va por --config en stdin, NO en argv. Con -u "$SONAR_TOKEN:" cualquier
  # usuario local lo leia con ps mientras la peticion estaba en vuelo. Las comillas y
  # las barras se escapan porque el formato de --config las interpreta.
  sonar_key_url="$(jq -rn --arg s "$sonar_key" '$s | @uri')"
  sonar_token_cfg="$(printf '%s' "$SONAR_TOKEN" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
  # --max-time: sin el, un host de Sonar que cuelga cuelga verify.sh para siempre.
  sonar_response="$(printf 'user = "%s:"\n' "$sonar_token_cfg" \
    | curl -sS --max-time "${HARNESS_SONAR_TIMEOUT:-60}" --config - \
        "${sonar_host}/api/qualitygates/project_status?projectKey=${sonar_key_url}" \
        2>/dev/null)"
  # Un cuerpo de error valido (401, 403, projectKey inexistente) no es un quality
  # gate en rojo: es no haber podido consultarlo. Mapearlo a fail era rojo falso, y
  # la regla dice que la incertidumbre es skipped.
  if printf '%s' "$sonar_response" | jq -e '.errors' >/dev/null 2>&1; then
    note "sonar: la API devolvio un error ($(printf '%s' "$sonar_response" \
      | jq -r '.errors[0].msg // "sin detalle"')) — gate saltado"
  else
    case "$(printf '%s' "$sonar_response" | jq -r '.projectStatus.status // "DESCONOCIDO"' 2>/dev/null)" in
      OK)    sonar_status="pass" ;;
      ERROR) sonar_status="fail" ;;
      *)     note "sonar: respuesta inesperada de la API — gate saltado" ;;
    esac
  fi
fi

# GitHub Actions: se salta si gh no está disponible o no hay run para el commit.
actions_status="skipped"
if ! command -v gh >/dev/null 2>&1; then
  note "actions: falta gh — gate saltado"
elif ! gh auth status >/dev/null 2>&1; then
  note "actions: gh sin autenticar — gate saltado"
else
  # Filtrado por COMMIT, no por repositorio. gh run list --limit 1 devolvia el run
  # mas reciente del repo entero, asi que un run verde en main hacia que este gate
  # reportara pass para una rama local que nunca paso por CI.
  head_sha="$(git rev-parse HEAD 2>/dev/null)"
  if [ -z "$head_sha" ]; then
    note "actions: no se pudo determinar el commit — gate saltado"
  else
    conclusion="$(gh run list --commit "$head_sha" --limit 1 \
      --json conclusion --jq '.[0].conclusion // ""' 2>/dev/null)"
    case "$conclusion" in
      success) actions_status="pass" ;;
      "")      note "actions: sin runs para el commit $head_sha — gate saltado" ;;
      *)       actions_status="fail" ;;
    esac
  fi
fi

# overall="pass" era el estado INICIAL y solo "fail" lo degradaba, asi que un estado
# vacio o desconocido — el sintoma de un ensamblado a medias — contaba como pass.
# Ahora la lista es blanca: solo pass y skipped dejan overall intacto. Un gate que no
# se sabe como salio no salio bien.
overall="pass"
coverage_status="$(printf '%s' "$coverage_json" | jq -r '.status' 2>/dev/null)"
for status in "$lint_status" "$tests_status" "$sonar_status" "$actions_status" \
              "$coverage_status"; do
  case "$status" in
    pass|skipped) ;;
    *)            overall="fail" ;;
  esac
done

# El jq -n final se captura antes de imprimirse. Suelto, si fallaba escribia nada en
# stdout y NO cambiaba el codigo de salida: verify.sh salia 0 sin haber reportado un
# solo gate, y task.sh lo leia como todo verde.
reporte="$(jq -n \
  --arg lint "$lint_status" \
  --arg tests "$tests_status" \
  --argjson coverage "${coverage_json:-null}" \
  --arg sonar "$sonar_status" \
  --arg actions "$actions_status" \
  --arg overall "$overall" \
  '{lint: $lint, tests: $tests, coverage: $coverage, sonar: $sonar, actions: $actions, overall: $overall}' \
  2>/dev/null)" || reporte=""

if [ -z "$reporte" ]; then
  # No es un gate rojo: es que jq no pudo ensamblar el JSON. Salir con EXIT_GATE hacia
  # que task.sh lo tradujera a "gates en rojo — la tarea sigue en implemented", que
  # manda a arreglar codigo cuando lo que falla es el entorno.
  note "no se pudo ensamblar el reporte de gates — no se declara nada verde sin poder reportarlo"
  exit "$EXIT_USAGE"
fi
printf '%s\n' "$reporte"

# El reporte se commitea y es lo que hace auditable un verified. Se escribe verde o
# rojo: su ausencia tiene que significar "no se verifico" y nada mas, asi que un fallo
# de escritura tiene que ser audible.
head_sha="$(git rev-parse HEAD 2>/dev/null)"
if [ -z "$head_sha" ]; then
  note "no se pudo determinar el commit — no se escribe reporte"
else
  # El reporte se nombra con HEAD, pero los gates corrieron sobre el arbol de trabajo.
  # Si el arbol esta sucio, ese nombre atesta un commit cuyo contenido NO es lo que se
  # verifico. Se registra la verdad y el lector decide: verify.sh sigue siendo util
  # mientras iteras, y un reporte sucio no puede respaldar un verified.
  if git diff --quiet HEAD 2>/dev/null && [ -z "$(git status --porcelain 2>/dev/null)" ]; then
    sucio=false
  else
    sucio=true
    note "arbol sucio — el reporte queda marcado y no podra respaldar un verified"
  fi

  destino="$AGENT_DIR/reports/$head_sha.json"
  mkdir -p "$AGENT_DIR/reports" 2>/dev/null

  # Un reporte que git no ve no puede respaldar ningun verified, y el silencio en este
  # caso borra la pista de auditoria sin avisar: los gates corren, el archivo aparece en
  # disco, y attest rechaza la tarea sin que nadie sepa por que.
  if git check-ignore -q "$destino" 2>/dev/null; then
    note "git ignora $destino — un reporte que git no ve no puede respaldar ningun verified; quita esa regla de .gitignore"
  fi

  # Se escribe a un temporal y se mueve, como ya hace task_set_field. Con `> "$destino"`
  # la redireccion TRUNCABA el archivo antes de que jq corriera y la rama de fallo lo
  # borraba, asi que una corrida fallida destruia un reporte valido anterior para ese
  # mismo sha. Mover tambien cierra la ventana entre dos corridas concurrentes.
  tmp_reporte="$(mktemp 2>/dev/null)" || tmp_reporte=""
  if [ -z "$tmp_reporte" ]; then
    note "no se pudo escribir $destino — no hubo temporal donde ensamblarlo"
  elif [ -d "$destino" ]; then
    rm -f "$tmp_reporte"
    note "no se pudo escribir $destino — hay un directorio en esa ruta"
  elif ! printf '%s' "$reporte" \
      | jq --arg sha "$head_sha" --argjson dirty "$sucio" '. + {sha: $sha, dirty: $dirty}' \
      > "$tmp_reporte" 2>/dev/null; then
    rm -f "$tmp_reporte"
    note "no se pudo escribir $destino — sin reporte no hay verified que se sostenga"
  elif ! mv "$tmp_reporte" "$destino" 2>/dev/null; then
    rm -f "$tmp_reporte"
    note "no se pudo escribir $destino — sin reporte no hay verified que se sostenga"
  fi
fi

[ "$overall" = "pass" ] && exit "$EXIT_OK"
exit "$EXIT_GATE"
