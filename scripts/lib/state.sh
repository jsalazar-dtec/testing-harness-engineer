#!/usr/bin/env bash
# Acceso a .agent/tasks.json. El estado del trabajo vive en el repo, no en el contexto:
# una sesión nueva se orienta leyendo estos archivos.

[ -n "${HARNESS_STATE_LOADED:-}" ] && return 0
HARNESS_STATE_LOADED=1

# shellcheck source=./common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_cmd jq

# El estado se resuelve desde la raiz del arbol de trabajo, no desde el cwd. Corriendo
# `task.sh attest T1` dentro de src/ el harness decia "no existe .agent/tasks.json —
# corre bootstrap.sh" con el archivo delante, y attest es justo lo que va a llamar un
# integrator o un job de CI desde donde le toque. En la raiz se deja la ruta relativa:
# es la que sale en los mensajes y la que la gente reconoce.
if [ -z "${AGENT_DIR:-}" ]; then
  AGENT_DIR=".agent"
  _harness_top="$(git rev-parse --show-toplevel 2>/dev/null)"
  if [ -n "$_harness_top" ] && [ "$_harness_top" != "$(pwd -P)" ]; then
    AGENT_DIR="$_harness_top/.agent"
  fi
  unset _harness_top
fi
# Se exporta para que verify.sh —que task.sh invoca como proceso hijo— lea el MISMO
# directorio. Sin exportarlo, task.sh podia estar mirando la raiz del repo mientras
# verify.sh escribia su reporte en ./.agent relativo al cwd.
export AGENT_DIR

tasks_file() {
  printf '%s/tasks.json' "$AGENT_DIR"
}

history_file() {
  printf '%s/history.jsonl' "$AGENT_DIR"
}

# Append de una linea JSON a history.jsonl. Idempotente en la forma (una linea,
# un objeto), no en el contenido: dos verified de la misma tarea son dos
# eventos distintos y los dos entran. Se escribe con >> a un archivo del repo,
# igual que tasks.json — es estado, y por eso vive en el repo, no en un
# transporte de mensajes.
#
# Falla abierto: si jq no puede componer el JSON o el disco no acepta la
# escritura, se avisa por stderr y se sigue. Un evento perdido es peor
# auditoria; un promote bloqueado por auditoria caida es peor operacion.
append_history() {
  local event="$1" task="${2:-}" detail_json="${3:-null}" ts registro
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  registro="$(jq -c -n \
      --arg ts "$ts" --arg event "$event" --arg task "$task" \
      --arg actor "task.sh" --argjson detail "$detail_json" \
      '{ts: $ts, event: $event, task: $task, actor: $actor, detail: $detail}' \
      2>/dev/null)" || {
    printf 'harness: no se pudo escribir el evento %s en history.jsonl — audita el promote a mano\n' \
      "$event" >&2
    return 0
  }
  printf '%s\n' "$registro" >> "$(history_file)" 2>/dev/null || {
    printf 'harness: no se pudo escribir history.jsonl — audita el promote a mano\n' >&2
    return 0
  }
}

# AGENT_DIR elige que tasks.json y que config.json se leen, y con eso elige que gates
# corren. Medido: con el config.json real en rojo, `AGENT_DIR=/tmp/falso task.sh verify
# T1` corria contra un config permisivo y producia un reporte GENUINO —sha real,
# overall pass, dirty false— para el HEAD real. Commiteado, attest decia 0 mientras
# verify.sh seguia saliendo 3. Leer el reporte de git no ayuda: ese reporte esta
# trackeado y es identico byte a byte a uno legitimo. La configuracion y el estado del
# harness viven en el repo, asi que se exige que esten dentro del arbol de trabajo.
#
# Devuelve el prefijo de AGENT_DIR relativo a la raiz (".agent/", o "" si AGENT_DIR es
# la raiz misma) porque es lo que necesitan `git ls-tree` y `git cat-file`: las rutas
# de objetos de git son relativas a la raiz, nunca absolutas.
_agent_prefix() {
  local top phys
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
  [ -n "$top" ] || return 1
  phys="$(cd "$AGENT_DIR" 2>/dev/null && pwd -P)" || return 1
  [ -n "$phys" ] || return 1
  case "$phys" in
    "$top")   printf '' ;;
    "$top"/*) printf '%s/' "${phys#"$top"/}" ;;
    *)        return 1 ;;
  esac
}

_require_agent_dir_en_arbol() {
  local top
  top="$(git rev-parse --show-toplevel 2>/dev/null)"
  # Fuera de un repo no hay arbol al que pertenecer y la comprobacion no aplica: quien
  # dependa de git —attest— ya se niega por su cuenta al no encontrar HEAD.
  [ -n "$top" ] || return 0
  _agent_prefix >/dev/null 2>&1 \
    || die "AGENT_DIR ($AGENT_DIR) no esta dentro del arbol de trabajo ($top) — el estado y la configuracion del harness viven en el repo"
}

_require_tasks_file() {
  [ -f "$(tasks_file)" ] || die "no existe $(tasks_file) — corre bootstrap.sh en este proyecto"
  [ ! -L "$(tasks_file)" ] || die "$(tasks_file) es un symlink — el estado tiene que ser un archivo del repo"
  _require_agent_dir_en_arbol
}

# El schema del config.json versiona la FORMA del archivo. Un cambio futuro que
# renombre `commands.testRelated` o mueva `sonar.host` fuera de `.sonar` sale
# aqui como un salto de version en vez de propagarse en silencio a proyectos ya
# adoptados. Se lee, no se escribe: quien migra un config viejo es
# scripts/doctor.sh, no cualquier script del harness que sourcee esta libreria.
readonly HARNESS_CONFIG_SCHEMA_SOPORTADO="harness/1"

_require_config_schema() {
  local config="$AGENT_DIR/config.json" schema
  [ -f "$config" ] || return 0
  jq -e . "$config" >/dev/null 2>&1 || return 0
  schema="$(jq -r '."$schema" // ""' "$config" 2>/dev/null)"
  [ -n "$schema" ] \
    || die "$config no declara \"\$schema\" — este harness espera \"$HARNESS_CONFIG_SCHEMA_SOPORTADO\"; corre scripts/doctor.sh migrate para migrar el config"
  [ "$schema" = "$HARNESS_CONFIG_SCHEMA_SOPORTADO" ] \
    || die "$config declara \"\$schema\": \"$schema\" — este harness solo entiende \"$HARNESS_CONFIG_SCHEMA_SOPORTADO\"; corre scripts/doctor.sh migrate"
}

task_count() {
  _require_tasks_file
  jq '.tasks | length' "$(tasks_file)"
}

task_field() {
  local id="$1" field="$2" value
  _require_tasks_file
  value="$(jq -r --arg id "$id" --arg f "$field" \
    '.tasks[] | select(.id == $id) | .[$f]' "$(tasks_file)")"
  # jq -r imprime la cadena literal "null" para un null de JSON, y branch y pr
  # nacen null en toda tarea. Sin este segundo chequeo, un campo sin valor se
  # leeria como si tuviera uno, y el integrator del plan 2 creeria que ya hay rama.
  [ -n "$value" ] && [ "$value" != "null" ] || return 1
  printf '%s' "$value"
}

task_status() {
  task_field "$1" status
}

task_next_valid() {
  case "$1" in
    pending)     printf 'implemented' ;;
    implemented) printf 'verified' ;;
    verified)    printf 'merged' ;;
    *)           return 1 ;;
  esac
}

task_set_field() {
  local id="$1" field="$2" value="$3" tmp
  _require_tasks_file
  task_status "$id" >/dev/null || die "tarea desconocida: $id"
  tmp="$(mktemp)"
  jq --arg id "$id" --arg f "$field" --arg v "$value" \
    '(.tasks[] | select(.id == $id) | .[$f]) = $v' "$(tasks_file)" > "$tmp"
  mv "$tmp" "$(tasks_file)"
}

task_set_status() {
  local id="$1" new="$2" current expected
  current="$(task_status "$id")" || die "tarea desconocida: $id"
  expected="$(task_next_valid "$current")" \
    || die "la tarea $id ya esta en estado final: $current"
  [ "$new" = "$expected" ] \
    || die "transicion invalida: $current -> $new (esperada: $expected)"
  # verified y merged son las dos afirmaciones de exito, y son las dos que exigen sello.
  # Antes esto solo lo comprobaba el hook, asi que sourcear esta libreria y llamar a la
  # funcion por su nombre promocionaba en una linea sin pasar por ningun hook.
  case "$new" in
    verified|merged)
      [ "${HARNESS_TASK_SH:-}" = "1" ] \
        || die "no puedes marcar $new directamente — usa task.sh verify, que corre los gates"
      ;;
  esac
  task_set_field "$id" status "$new"

  # Un verdict de reviewer o business-reviewer vale para el diff que juzgo, no para
  # el siguiente. Salir de implemented (hoy, la unica arista es implemented ->
  # verified) es la señal de que ese diff ya no es el que esta bajo revision, asi
  # que una aprobacion vieja no puede sobrevivir sin re-revisarse.
  [ "$current" = "implemented" ] || return 0
  _task_reset_reviews "$id"
}

# Interno: reviews vuelve a { tecnico: null, negocio: null }. No pide sello por su
# cuenta porque solo se llama desde dentro de task_set_status, que ya lo exigio para
# la transicion que la dispara.
_task_reset_reviews() {
  local id="$1" tmp
  tmp="$(mktemp)"
  jq --arg id "$id" \
    '(.tasks[] | select(.id == $id) | .reviews) = {tecnico: null, negocio: null}' \
    "$(tasks_file)" > "$tmp"
  mv "$tmp" "$(tasks_file)"
}

# Lee un veredicto de revision. Devuelve 1 (sin imprimir nada) si no esta puesto —
# ni "ok" ni "rechaza", sea porque nunca se reviso o porque acaba de resetearse. El
# mismo tratamiento que task_field le da a branch/pr: "null" de JSON no es un valor.
task_review() {
  local id="$1" quien="$2" value
  _require_tasks_file
  value="$(jq -r --arg id "$id" --arg q "$quien" \
    '.tasks[] | select(.id == $id) | .reviews[$q]' "$(tasks_file)" 2>/dev/null)"
  [ -n "$value" ] && [ "$value" != "null" ] || return 1
  printf '%s' "$value"
}

# Escribe un veredicto de revision. Sellado como verified/merged: reviewer y
# business-reviewer no tienen Write, asi que quien puede invocar esto es la sesion
# orquestadora a traves de task.sh review — nunca el rol que emite el veredicto, y
# nunca un hand-edit que sourcee esta libreria por su cuenta.
task_set_review() {
  local id="$1" quien="$2" veredicto="$3" tmp
  _require_tasks_file
  task_status "$id" >/dev/null || die "tarea desconocida: $id"
  [ "${HARNESS_TASK_SH:-}" = "1" ] \
    || die "no puedes escribir una revision directamente — usa task.sh review, que deja el sello de quien registra el veredicto"
  tmp="$(mktemp)"
  jq --arg id "$id" --arg q "$quien" --arg v "$veredicto" \
    '(.tasks[] | select(.id == $id) | .reviews[$q]) = $v' "$(tasks_file)" > "$tmp"
  mv "$tmp" "$(tasks_file)"
}

task_blockers() {
  local id="$1" blockers unknown
  _require_tasks_file

  # Una dependencia que no existe no puede estar merged. Ignorarla en silencio
  # significaria que un id mal escrito DESBLOQUEA la tarea en vez de detenerla,
  # que es el fallo exacto que este harness existe para impedir.
  unknown="$(jq -r --arg id "$id" '
    [ .tasks[].id ] as $ids
    | .tasks[] | select(.id == $id) | .dependsOn[]?
    | select(. as $dep | ($ids | index($dep)) == null)' "$(tasks_file)")"
  [ -z "$unknown" ] \
    || die "dependencia desconocida de $id: $(printf '%s' "$unknown" | tr '\n' ' ' | sed 's/ $//')"

  blockers="$(jq -r --arg id "$id" '
    .tasks as $all
    | [ $all[] | select(.id == $id) | .dependsOn[]? ] as $deps
    | $all[]
    | select((.id | IN($deps[])) and .status != "merged")
    | .id' "$(tasks_file)")"
  [ -z "$blockers" ] && return 0
  printf '%s' "$blockers"
  return 1
}

# Un verified solo cuenta si hay una atestacion de task.sh verify COMMITEADA que
# nombre esa tarea, ese commit y el config.json que corrio los gates. Esto es la
# imposicion: deja de importar COMO se escribio el estado, porque la pregunta se hace
# al LEERLO y es una sola.
#
# Lee de git, nunca del disco. `[ -f ]` y `[ ! -L ]` miran el arbol de trabajo, y por
# ahi pasaban cuatro rutas medidas: un reporte que nunca paso por `git add`, un hard
# link a un archivo de fuera del repo, un `.agent/reports` que es symlink a otro
# directorio, y un `reports/` en .gitignore. Ninguno de los cuatro existe para git.
#
# NO llama a die: el llamador la invoca dentro de $( ) para capturar el motivo, y un
# exit desde ahi solo mataria la subshell. Es el defecto C5 del review final, que hacia
# que el guard imprimiera "bloqueado" y saliera 0. Devuelve estado y deja decidir.
task_attested() {
  local id="$1" estado sha prefijo reporte modo contenido overall derivado
  local tarea sha_reporte hash_registrado hash_commiteado
  local gate_lint gate_tests gate_coverage
  if ! estado="$(task_status "$id")"; then
    printf 'tarea desconocida: %s\n' "$id"
    return 1
  fi

  # Solo verified y merged necesitan respaldo. El resto no afirma exito.
  case "$estado" in
    verified|merged) ;;
    *) return 0 ;;
  esac

  # El id entra en la ruta del artefacto de atestacion, y sale de tasks.json, que es un
  # archivo influible. Un id con ".." o con "/" construiria una ruta que no es la que
  # este harness quiere leer.
  case "$id" in
    ''|.*|*..*|*[!A-Za-z0-9._-]*)
      printf 'el id %s no puede formar la ruta de un reporte: se admiten letras, digitos, punto, guion y guion bajo\n' "$id"
      return 1
      ;;
  esac

  if ! sha="$(task_field "$id" verifiedAt)"; then
    printf 'la tarea %s dice %s sin verifiedAt — no se promovio por task.sh verify\n' "$id" "$estado"
    return 1
  fi

  # verifiedAt sale del archivo de estado, asi que es un valor influible. Concatenarlo
  # a una ruta sin validar permitia que un "../../.." hiciera que attest aceptara un
  # reporte fabricado FUERA del repo — peor que el limite que el spec acepta, porque
  # ese reporte no aparece en el diff del PR: solo cambia una cadena en tasks.json.
  if ! printf '%s' "$sha" | grep -qE '^[0-9a-f]{40}$'; then
    printf 'la tarea %s tiene un verifiedAt que no es un sha: %s\n' "$id" "$sha"
    return 1
  fi
  if ! git rev-parse --verify --quiet "$sha^{commit}" >/dev/null 2>&1; then
    printf 'la tarea %s dice %s en un commit que no existe aqui: %s\n' "$id" "$estado" "$sha"
    return 1
  fi
  # Y tiene que estar en la historia de HEAD: un sha real de otra rama con reporte
  # verde respaldaria una tarea cuyos cambios ese reporte nunca cubrio.
  if ! git merge-base --is-ancestor "$sha" HEAD 2>/dev/null; then
    printf 'la tarea %s dice %s en un commit que no es ancestro de HEAD: %s\n' "$id" "$estado" "$sha"
    return 1
  fi

  if ! prefijo="$(_agent_prefix)"; then
    printf 'no se pudo situar %s dentro del arbol de trabajo — el reporte se lee del repo, no del disco\n' "$AGENT_DIR"
    return 1
  fi

  # El artefacto de atestacion es POR TAREA, no por commit. Con un solo <sha>.json
  # nada ataba el reporte a la tarea: el reporte verde de T1 respaldaba a T2 con los
  # gates en rojo cambiando una linea de tasks.json, sin fabricar nada. Y en la otra
  # direccion, dos tareas verificadas en el mismo commit compartian archivo, asi que
  # un verify ROJO de la segunda sobrescribia el reporte verde de la primera y le
  # destruia la atestacion. El nombre por-sha estaba mal en los dos sentidos.
  reporte="${prefijo}reports/$sha-$id.json"

  # Se lee en HEAD, no en $sha, y es a proposito: task.sh verify escribe la atestacion
  # DESPUES de que $sha exista, asi que el artefacto se commitea en un descendiente.
  # Leer "$sha:$reporte" rechazaria toda atestacion legitima. Lo que ata el veredicto
  # al codigo es la comprobacion de ancestria de arriba, no en que arbol se lea el
  # archivo. El modo tiene que ser exactamente 100644: 120000 es un symlink y 160000
  # un submodulo, y ninguno de los dos es un reporte de este repo.
  modo="$(git ls-tree --full-tree HEAD -- "$reporte" 2>/dev/null | awk '{print $1}')"
  if [ "$modo" != "100644" ]; then
    printf 'la tarea %s dice %s sin reporte commiteado en %s (git ve: %s) — un reporte que git no ve no es evidencia\n' \
      "$id" "$estado" "$reporte" "${modo:-nada}"
    return 1
  fi
  if ! contenido="$(git cat-file blob "HEAD:$reporte" 2>/dev/null)" || [ -z "$contenido" ]; then
    printf 'no se pudo leer del repo el reporte de %s en %s\n' "$id" "$reporte"
    return 1
  fi

  # A partir de aqui SOLO se parsea $contenido. Volver al archivo del disco reabriria
  # las cuatro rutas de golpe: lo que git guarda y lo que hay en el arbol de trabajo
  # no tienen por que ser lo mismo.
  tarea="$(printf '%s' "$contenido" | jq -r '.task // ""' 2>/dev/null)"
  if [ "$tarea" != "$id" ]; then
    printf 'el reporte de %s en %s no nombra esa tarea (dice: %s) — una atestacion vale para la tarea que declara y para ninguna otra\n' \
      "$id" "$reporte" "${tarea:-nada}"
    return 1
  fi
  sha_reporte="$(printf '%s' "$contenido" | jq -r '.sha // ""' 2>/dev/null)"
  if [ "$sha_reporte" != "$sha" ]; then
    printf 'el reporte de %s dice haberse generado en %s y la tarea dice %s\n' \
      "$id" "${sha_reporte:-nada}" "$sha"
    return 1
  fi

  overall="$(printf '%s' "$contenido" | jq -r '.overall // ""' 2>/dev/null)"
  if [ "$overall" != "pass" ]; then
    printf 'la tarea %s dice %s con reporte en rojo (%s) para %s\n' \
      "$id" "$estado" "${overall:-ilegible}" "$sha"
    return 1
  fi

  # overall se RE-DERIVA con la misma lista blanca que usa verify.sh en vez de creerselo.
  # Esta fase existe porque el lector no puede suponer que el escritor produjo el
  # archivo: {"overall":"pass","tests":"fail","dirty":false} atestaba limpio. Solo pass
  # y skipped dejan el veredicto intacto; un gate ausente o con un valor desconocido no
  # salio bien.
  derivado="$(printf '%s' "$contenido" | jq -r '
    def verde: . == "pass" or . == "skipped";
    if ((.lint | verde) and (.tests | verde) and (.coverage.status? | verde)
        and (.sonar | verde) and (.actions | verde))
    then "pass" else "fail" end' 2>/dev/null)"
  if [ "$derivado" != "pass" ]; then
    printf 'el reporte de %s para %s se declara pass pero sus gates no lo estan (re-derivado: %s) — el lector no se cree el veredicto, lo recalcula\n' \
      "$id" "$sha" "${derivado:-ilegible}"
    return 1
  fi

  # task.sh verify exige, antes de promover, que al menos un gate ejecutable (lint,
  # tests o coverage) no sea skipped: con el config.json de fabrica los cuatro
  # comandos son null, los tres quedan skipped, y esa tarea nunca llega a verified
  # por esa via. Pero un reporte hecho a mano con esos tres gates en skipped y
  # overall en "pass" pasa intacto por el re-derivado de arriba (skipped cuenta como
  # verde) y por el resto de esta funcion: nombra la tarea correcta, el commit
  # correcto y el configHash de un config.json real y sin tocar. No hace falta
  # mentir en nada. Si esta funcion no repite aqui la misma regla que el escritor,
  # el lector queda MAS PERMISIVO que el, que es exactamente la asimetria que esta
  # fase existe para cerrar: sonar y actions no cuentan, igual que en task.sh, porque
  # ambos degradan a skipped por falta de red o credenciales.
  gate_lint="$(printf '%s' "$contenido" | jq -r '.lint // ""' 2>/dev/null)"
  gate_tests="$(printf '%s' "$contenido" | jq -r '.tests // ""' 2>/dev/null)"
  gate_coverage="$(printf '%s' "$contenido" | jq -r '.coverage.status // ""' 2>/dev/null)"
  if [ "$gate_lint" != "pass" ] && [ "$gate_tests" != "pass" ] && [ "$gate_coverage" != "pass" ]; then
    printf 'el reporte de %s para %s no registra ningun gate que realmente corriera (lint, tests y coverage estan skipped) — vuelve a correr task.sh verify %s con commands configurados en config.json\n' \
      "$id" "$sha" "$id"
    return 1
  fi

  # Un reporte de arbol sucio nombra un commit cuyo contenido no es lo que se verifico.
  # Solo un false EXPLICITO se lee como limpio: true, null, campo ausente o cualquier
  # otro valor fallan cerrado. No se usa `.dirty // true` porque el operador // de jq
  # devuelve el lado derecho tambien cuando el izquierdo es false, asi que un reporte
  # limpio se habria leido como sucio y attest habria rechazado todo.
  if [ "$(printf '%s' "$contenido" | jq -r 'if .dirty == false then "false" else "true" end' 2>/dev/null)" != "false" ]; then
    printf 'la tarea %s dice %s con un reporte de arbol sucio para %s\n' "$id" "$estado" "$sha"
    return 1
  fi

  # Y los gates que corrieron tienen que ser los que estan en el repo. AGENT_DIR fuera
  # del arbol ya se rechaza antes, pero registrar el hash del config.json que produjo
  # el reporte es lo que hace el limite REVISABLE: un revisor puede sacar ese blob y
  # ver que lint no era "true".
  hash_registrado="$(printf '%s' "$contenido" | jq -r '.configHash // ""' 2>/dev/null)"
  if ! printf '%s' "$hash_registrado" | grep -qE '^[0-9a-f]{40}$'; then
    printf 'el reporte de %s para %s no registra el configHash del config.json que corrio los gates\n' "$id" "$sha"
    return 1
  fi
  hash_commiteado="$(git rev-parse --verify --quiet "$sha:${prefijo}config.json" 2>/dev/null)"
  if [ -z "$hash_commiteado" ]; then
    printf 'no hay %sconfig.json commiteado en %s — sin el no se puede comprobar que gates corrieron\n' \
      "$prefijo" "$sha"
    return 1
  fi
  if [ "$hash_registrado" != "$hash_commiteado" ]; then
    printf 'el reporte de %s se genero con un config.json que no es el commiteado en %s — los gates que corrieron no son los del repo\n' \
      "$id" "$sha"
    return 1
  fi
}
