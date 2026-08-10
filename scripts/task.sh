#!/usr/bin/env bash
# CLI del estado de tareas. No toca git: solo lee y escribe .agent/tasks.json.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/state.sh
. "$HERE/lib/state.sh"

usage() {
  cat >&2 <<'TXT'
uso: task.sh <subcomando>

  list                     lista las tareas con su estado
  show <id>                imprime el JSON de una tarea
  start <id>               valida dependencias e imprime el nombre de rama
  start-worktree <id>      como start, pero crea el worktree en .worktrees/<id>/
  implemented <id>         marca la tarea como implementada
  verify <id>              corre los gates y solo con todo verde marca verified
  merged <id> --pr <n>     marca la tarea como mergeada
  attest <id>              responde si un verified esta respaldado por su reporte
  review <id> --por tecnico|negocio --veredicto ok|rechaza
                           registra el veredicto de un revisor sobre una tarea implemented
  sync                     trae Issues de GitHub asignados al usuario autenticado como borradores locales
  intake <numero> --acepta
                           acepta el borrador del Issue: lo etiqueta harness:synced y lo vuelve spec
  intake <numero> --rechaza --comentario "<texto>"
                           rechaza el borrador: comenta en el Issue, lo etiqueta harness:needs-info y borra el borrador
TXT
  exit "$EXIT_USAGE"
}

# LC_ALL=C a proposito: [:alnum:] depende del locale, asi que "Autenticación de
# usuarios" daba feat/T1-autenticación-de-usuarios bajo UTF-8 y
# feat/T1-autenticaci-n-de-usuarios bajo LC_ALL=C. El nombre de rama se PERSISTE en
# tasks.json y lo va a consumir el integrator del plan 2, asi que no puede depender
# del entorno de quien corrio el comando. Fijarlo a C da siempre la version ASCII.
slugify() {
  LC_ALL=C printf '%s' "$1" \
    | LC_ALL=C tr '[:upper:]' '[:lower:]' \
    | LC_ALL=C tr -cs '[:alnum:]' '-' \
    | LC_ALL=C sed -e 's/^-*//' -e 's/-*$//'
}

cmd_list() {
  local id estado titulo marca
  while IFS="$(printf '\t')" read -r id estado titulo; do
    marca=" "
    task_attested "$id" >/dev/null 2>&1 || marca="!"
    printf '%s %s\t%s\t%s\n' "$marca" "$id" "$estado" "$titulo"
  done <<TAREAS
$(jq -r '.tasks[] | "\(.id)\t\(.status)\t\(.title)"' "$(tasks_file)")
TAREAS
}

cmd_show() {
  local id="${1:-}"
  [ -n "$id" ] || usage
  jq --arg id "$id" '.tasks[] | select(.id == $id)' "$(tasks_file)"
}

cmd_start() {
  local id="${1:-}" blockers branch
  [ -n "$id" ] || usage
  task_status "$id" >/dev/null || die "tarea desconocida: $id"
  if ! blockers="$(task_blockers "$id")"; then
    # task_blockers falla por dos motivos distintos: hay bloqueantes, o alguna
    # dependencia no existe. En el segundo ya murio explicando la causa por
    # stderr y su stdout viene vacio: anadir "bloqueada por: " sin lista
    # contradiria el mensaje que el usuario acaba de leer.
    [ -n "$blockers" ] || exit "$EXIT_USAGE"
    die "$id esta bloqueada por: $(printf '%s' "$blockers" | tr '\n' ' ' | sed 's/ $//')"
  fi
  branch="feat/$id-$(slugify "$(task_field "$id" title)")"
  task_set_field "$id" branch "$branch"
  append_history start "$id" "$(jq -n --arg b "$branch" '{branch: $b}')"
  printf '%s\n' "$branch"
}

cmd_implemented() {
  local id="${1:-}"
  [ -n "$id" ] || usage
  task_set_status "$id" implemented
  append_history implemented "$id" null
}

# start-worktree: mismo contrato que start, mas la creacion del worktree. Se
# invoca cuando pipeline.sh parallel identifico varias tareas independientes y
# se quiere avanzar dos o mas en simultaneo sin que se pisen la rama.
#
# Idempotente: si el worktree ya existe (por ejemplo tras una sesion previa),
# no lo recrea; imprime igual la ruta para que el llamador entre.
cmd_start_worktree() {
  local id="${1:-}" branch worktree top
  [ -n "$id" ] || usage
  require_cmd git

  top="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || die "start-worktree solo tiene sentido dentro de un repo git"

  # La creacion de rama y la validacion de dependencias vive en cmd_start:
  # se reutiliza para no duplicar la logica de slug, sello ni append_history.
  branch="$(cmd_start "$id")"
  worktree="$top/.worktrees/$id"

  if [ -d "$worktree" ]; then
    printf 'harness: worktree ya existe en %s — entra ahi (cd) y sigue\n' "$worktree" >&2
    printf '%s\n' "$worktree"
    return 0
  fi

  mkdir -p "$top/.worktrees"
  # -B: mueve la rama si ya existia; task_set_field ya la registro con el nombre
  # exacto. No hay --track: la rama sale de HEAD del repo principal, que es de
  # donde el implementer arrancaria en la rama serial. Si el proyecto necesita
  # arrancar desde la rama de integracion, hazlo commiteando primero en ella.
  git worktree add -B "$branch" "$worktree" >/dev/null \
    || die "no se pudo crear el worktree en $worktree — comprobalo con 'git worktree list'"

  printf 'harness: worktree creado en %s con la rama %s — cd ahi para trabajar\n' \
    "$worktree" "$branch" >&2
  printf '%s\n' "$worktree"
}

cmd_merged() {
  local id="${1:-}" pr="" motivo
  [ -n "$id" ] || usage
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --pr)
        # Sin este chequeo el shift 2 falla cuando solo queda un parametro, y
        # set -e mata el script ahi mismo: exit 1 sin ningun mensaje. Un error
        # silencioso en la herramienta que gobierna el estado no es aceptable.
        [ $# -ge 2 ] || die "--pr requiere un numero de PR"
        pr="$2"
        shift 2
        ;;
      *)    usage ;;
    esac
  done
  [ -n "$pr" ] || die "merged requiere --pr <numero>: el estado merged se toma del PR real"

  # merged es el estado terminal de exito Y lo que desbloquea las dependencias, asi que
  # es la afirmacion mas fuerte que este harness hace. Se comprueba con la misma pregunta
  # que attest: promover sin ella dejaba pasar a merged cualquier verified sin respaldo,
  # y de ahi arrancaban las tareas que dependian de el.
  if ! motivo="$(task_attested "$id")"; then
    printf 'harness: %s\n' "$motivo" >&2
    printf 'harness: %s no se marca merged sin atestacion — corre task.sh attest %s y arregla lo que diga\n' \
      "$id" "$id" >&2
    exit "$EXIT_GATE"
  fi

  HARNESS_TASK_SH=1 task_set_status "$id" merged
  task_set_field "$id" pr "$pr"
  append_history merged "$id" "$(jq -n --arg pr "$pr" '{pr: $pr}')"
}

cmd_attest() {
  local id="${1:-}" motivo
  [ -n "$id" ] || usage
  # Un id que no existe es error de uso (1), no un gate rojo (3). Se comprueba aqui
  # para que los dos casos no salgan con el mismo codigo.
  task_status "$id" >/dev/null || die "tarea desconocida: $id"
  if ! motivo="$(task_attested "$id")"; then
    printf 'harness: %s\n' "$motivo" >&2
    exit "$EXIT_GATE"
  fi
}

cmd_verify() {
  local id="${1:-}" current_status output status overall head_sha
  local gate_lint gate_tests gate_coverage registro atestacion tmp_atestacion config_hash
  [ -n "$id" ] || usage
  current_status="$(task_status "$id")" \
    || die "tarea desconocida: $id"
  # "transicion invalida: verified -> verified (esperada desde implemented)" describe una
  # arista del grafo, no lo que le pasa a quien lo lee. Quien vuelve a verificar una
  # tarea ya verificada quiere saber si su atestacion se sostiene, y eso lo contesta
  # attest.
  [ "$current_status" != "verified" ] \
    || die "la tarea $id ya esta en verified — corre task.sh attest $id para comprobar si su reporte la respalda"
  [ "$current_status" = "implemented" ] \
    || die "transicion invalida: $current_status -> verified (esperada desde implemented)"

  # Un gate en verde y una revision aprobada son capas distintas: la una mide el
  # codigo, la otra el juicio de negocio y de calidad. Ninguna sustituye a la otra.
  local tecnico negocio
  tecnico="$(task_review "$id" tecnico)" || tecnico=""
  negocio="$(task_review "$id" negocio)" || negocio=""
  if [ "$tecnico" != "ok" ] || [ "$negocio" != "ok" ]; then
    die "$id no tiene las dos revisiones en ok (tecnico=${tecnico:-null}, negocio=${negocio:-null}) — corre task.sh review $id --por tecnico|negocio --veredicto ok antes de verify"
  fi

  set +e
  output="$("$HERE/verify.sh")"
  status=$?
  set -e

  printf '%s\n' "$output"

  # verify.sh sale 1 cuando el entorno esta incompleto y 3 cuando un gate esta rojo.
  # Colapsar ambos en 3 le decia al rol que hay trabajo que arreglar cuando lo que
  # falta es configuracion. Y salir con 1 en silencio no le decia nada.
  if [ "$status" -eq "$EXIT_USAGE" ]; then
    printf 'harness: verify.sh no pudo correr — revisa el entorno del proyecto\n' >&2
    exit "$EXIT_USAGE"
  fi
  if [ "$status" -ne 0 ]; then
    printf 'harness: gates en rojo — la tarea %s sigue en implemented\n' "$id" >&2
    exit "$EXIT_GATE"
  fi

  # Ultima linea de defensa: no basta el exit 0, hay que LEER el reporte. verify.sh
  # llego a salir 0 con stdout vacio cuando su propio ensamblado de JSON fallaba, y
  # la tarea alcanzaba verified habiendo medido nada. Sin overall == "pass" leido del
  # JSON, esto no promueve.
  overall="$(printf '%s' "$output" | jq -r '.overall // empty' 2>/dev/null)" || overall=""
  if [ "$overall" != "pass" ]; then
    printf 'harness: verify.sh salio con 0 pero su reporte no dice overall pass (leido: %s) — la tarea %s sigue en implemented\n' \
      "${overall:-nada}" "$id" >&2
    exit "$EXIT_GATE"
  fi

  # Un gate que no corrio es skipped, y skipped no rompe overall: un proyecto de
  # Terraform sin tests unitarios tiene que poder verificar. Pero skipped tampoco es
  # passed. Con el config.json de fabrica los cuatro comandos son null, todos los
  # gates quedan skipped y overall es pass: un harness recien adoptado aprobaba cada
  # tarea habiendo medido nada. verify.sh mantiene su contrato; la puerta se cierra
  # aqui, que es donde se decide una promocion.
  #
  # lint CUENTA como gate ejecutable. Exigir tests o coverage contradecia el parrafo de
  # arriba: con lint="true" y el resto en null la tarea no llegaba a verified nunca, asi
  # que el proyecto de Terraform sin tests unitarios que el comentario dice que tiene que
  # poder verificar no podia. Sonar y Actions siguen sin contar: los dos degradan a
  # skipped por falta de red o de credenciales, asi que apoyar la promocion en ellos
  # haria que un corte de red decidiera si una tarea puede avanzar.
  gate_lint="$(printf '%s' "$output" | jq -r '.lint // empty' 2>/dev/null)"
  gate_tests="$(printf '%s' "$output" | jq -r '.tests // empty' 2>/dev/null)"
  gate_coverage="$(printf '%s' "$output" | jq -r '.coverage.status // empty' 2>/dev/null)"
  if [ "$gate_lint" = "skipped" ] && [ "$gate_tests" = "skipped" ] \
     && [ "$gate_coverage" = "skipped" ]; then
    printf 'harness: ningun gate ejecutable configurado (lint, tests y coverage estan skipped) — rellena commands en .agent/config.json\n' >&2
    exit "$EXIT_USAGE"
  fi

  head_sha="$(git rev-parse HEAD 2>/dev/null)" \
    || die "no se pudo determinar el commit para registrar la verificacion"
  [ -n "$head_sha" ] || die "no se pudo determinar el commit para registrar la verificacion"

  registro="$AGENT_DIR/reports/$head_sha.json"
  [ -f "$registro" ] \
    || die "verify.sh no dejo su registro en $registro — sin reporte en disco no hay verified que se sostenga"

  # Se LEE el reporte que este mismo comando acaba de causar. verify.sh marca el reporte
  # sucio y sale 0, y promover de todas formas dejaba la tarea en un estado sin salida:
  # verified para siempre, attest rechazandola para siempre, commitear despues no
  # arreglaba nada, y volver a correr verify chocaba con "transicion invalida: verified
  # -> verified" porque no hay arista de vuelta. La unica escapatoria era editar
  # tasks.json a mano, que es justo lo que el hook bloquea. Se para aqui, donde todavia
  # se puede.
  #
  # No es un gate rojo: los gates salieron verdes. Lo que no esta en el commit es el
  # arbol de quien verifica, asi que sale 1.
  if [ "$(jq -r 'if .dirty == false then "false" else "true" end' "$registro" 2>/dev/null)" != "false" ]; then
    printf 'harness: los gates corrieron sobre un arbol sucio, asi que su reporte no puede respaldar a %s — commitea los cambios y vuelve a correr task.sh verify %s\n' \
      "$id" "$id" >&2
    exit "$EXIT_USAGE"
  fi

  # El id entra en la ruta del artefacto. Se valida con la misma regla que task_attested
  # usa al leerlo: si no puede formar una ruta, no se escribe nada.
  case "$id" in
    ''|.*|*..*|*[!A-Za-z0-9._-]*)
      die "el id $id no puede formar la ruta de un reporte: se admiten letras, digitos, punto, guion y guion bajo"
      ;;
  esac

  # El hash del config.json que REALMENTE corrio los gates. task_attested lo compara
  # contra el config.json commiteado en $head_sha: si no coinciden, los gates que
  # corrieron no son los que estan en el repo.
  config_hash="$(git hash-object "$AGENT_DIR/config.json" 2>/dev/null)"
  printf '%s' "$config_hash" | grep -qE '^[0-9a-f]{40}$' \
    || die "no se pudo hashear $AGENT_DIR/config.json — sin ese hash el reporte no puede decir que gates corrieron"

  # El artefacto de atestacion es por TAREA. verify.sh no conoce el id y no tiene por
  # que conocerlo: escribe el registro de la corrida, que es <sha>.json, y attest no lo
  # lee nunca. La evidencia que respalda una tarea la escribe quien sabe de que tarea
  # se trata.
  atestacion="$AGENT_DIR/reports/$head_sha-$id.json"
  tmp_atestacion="$(mktemp)" \
    || die "no se pudo crear un temporal para la atestacion de $id"
  if ! jq --arg t "$id" --arg h "$config_hash" '. + {task: $t, configHash: $h}' \
      "$registro" > "$tmp_atestacion" 2>/dev/null; then
    rm -f "$tmp_atestacion"
    die "no se pudo ensamblar la atestacion $atestacion — sin evidencia ligada a la tarea no hay verified"
  fi
  mv "$tmp_atestacion" "$atestacion" 2>/dev/null \
    || { rm -f "$tmp_atestacion"; die "no se pudo escribir $atestacion — sin evidencia ligada a la tarea no hay verified"; }

  HARNESS_TASK_SH=1 task_set_field "$id" verifiedAt "$head_sha"
  # El sello autoriza al hook a aceptar la escritura de verified. No es
  # criptografía: es la barrera contra el atajo accidental, que es el fallo real.
  HARNESS_TASK_SH=1 task_set_status "$id" verified
  append_history verified "$id" "$(jq -n --arg s "$head_sha" --arg h "$config_hash" '{sha: $s, configHash: $h}')"

  # attest lee la atestacion de GIT, no del disco, asi que este paso no es cosmetico:
  # sin commitear, `task.sh attest` sigue diciendo que la tarea no tiene respaldo.
  printf 'harness: atestacion escrita en %s — commiteala junto a %s; attest la lee de git, no del disco\n' \
    "$atestacion" "$(tasks_file)" >&2
}

# reviewer y business-reviewer no tienen Write ni Bash de escritura: por diseno no
# pueden dejar en disco ningun rastro de "ya revise esto". Este comando es lo que
# hace durable su veredicto, y lo escribe la sesion orquestadora — nunca el propio
# rol — con lo que ese rol sigue sin poder aprobarse a si mismo.
cmd_review() {
  local id="${1:-}" por="" veredicto=""
  [ -n "$id" ] || usage
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --por)
        [ $# -ge 2 ] || die "--por requiere tecnico o negocio"
        por="$2"
        shift 2
        ;;
      --veredicto)
        [ $# -ge 2 ] || die "--veredicto requiere ok o rechaza"
        veredicto="$2"
        shift 2
        ;;
      *) usage ;;
    esac
  done

  case "$por" in
    tecnico|negocio) ;;
    *) die "--por desconocido: '${por}' — usa tecnico o negocio" ;;
  esac
  case "$veredicto" in
    ok|rechaza) ;;
    *) die "--veredicto desconocido: '${veredicto}' — usa ok o rechaza" ;;
  esac

  local current
  current="$(task_status "$id")" || die "tarea desconocida: $id"
  [ "$current" = "implemented" ] \
    || die "$id no esta en implemented (esta en $current) — solo se registran revisiones sobre una tarea implementada"

  HARNESS_TASK_SH=1 task_set_review "$id" "$por" "$veredicto"
  append_history review "$id" "$(jq -n --arg p "$por" --arg v "$veredicto" '{por: $p, veredicto: $v}')"
  printf 'harness: revision de %s registrada — %s: %s\n' "$id" "$por" "$veredicto"
}

# task.sh sync trae Issues de GitHub asignados al usuario autenticado de gh y
# los deja como borradores locales en .agent/specs/. No decide si un Issue
# esta completo — eso lo juzga el rol intake-reviewer sobre el archivo que
# este comando escribe; pipeline.sh lo encuentra por el sufijo -DRAFT.md.
#
# gh no se llama con --jq: se parsea su salida con jq propio, igual que el
# resto del harness trata la salida de herramientas externas.
cmd_sync() {
  require_cmd gh
  local user issues_json today vistos=0

  user="$(gh api user 2>/dev/null | jq -r '.login // empty')" \
    || die "no se pudo resolver el usuario autenticado de gh — corre 'gh auth login'"
  [ -n "$user" ] \
    || die "no se pudo resolver el usuario autenticado de gh — corre 'gh auth login'"

  issues_json="$(gh issue list \
    --search "assignee:$user is:open is:issue -label:harness:synced" \
    --json number,title,body,url 2>/dev/null)" \
    || die "no se pudo listar issues de gh"
  printf '%s' "$issues_json" | jq -e . >/dev/null 2>&1 \
    || die "gh issue list no devolvio JSON valido"

  mkdir -p "$AGENT_DIR/specs"
  today="$(date +%Y-%m-%d)"

  while IFS= read -r linea; do
    [ -n "$linea" ] || continue
    vistos=$((vistos + 1))
    local number title body url archivo
    # // "" en cada campo de texto: un Issue sin cuerpo llega con body null, y
    # jq -r imprimiria la cadena literal "null" en el borrador — el
    # intake-reviewer leeria "null" como si fuera la descripcion del Issue.
    number="$(printf '%s' "$linea" | jq -r '.number')"
    title="$(printf '%s' "$linea" | jq -r '.title // ""')"
    body="$(printf '%s' "$linea" | jq -r '.body // ""')"
    url="$(printf '%s' "$linea" | jq -r '.url // ""')"
    archivo="$AGENT_DIR/specs/${today}-issue-${number}-DRAFT.md"
    {
      printf '<!-- issue: %s -->\n' "$number"
      printf '# %s\n\n' "$title"
      printf '%s\n\n' "$body"
      printf 'Fuente: %s\n' "$url"
    } > "$archivo"
    printf 'harness: borrador de issue #%s escrito en %s\n' "$number" "$archivo"
  done <<LISTA
$(printf '%s' "$issues_json" | jq -c '.[]')
LISTA

  # A stdout: es un exito informativo (exit 0), no un error.
  [ "$vistos" -gt 0 ] \
    || printf 'harness: no hay issues nuevos asignados a %s\n' "$user"
}

# task.sh intake cierra el ciclo de vida del borrador que cmd_sync abre. El mv y
# el rm viven DENTRO de este script a proposito: cmdscan.sh clasifica cualquier
# ruta bajo .agent/specs/ como clase protegida, y protect_artifacts.sh solo
# inspecciona el TEXTO del comando Bash que el agente tipea — no lo que un script
# invocado hace por dentro. Es la misma tecnica por la que task.sh review y
# task.sh verify pueden escribir tasks.json. Sin esto, ni aceptar ni descartar un
# borrador era posible desde una sesion de Claude, y el primer sync dejaba el
# pipeline sin poder avanzar nada.
#
# No lleva el sello HARNESS_TASK_SH: no toca tasks.json ni config.json, que son
# las unicas clases que el hook exige sellar.
cmd_intake() {
  local numero="${1:-}" modo="" comentario="" borrador conteo
  [ -n "$numero" ] || usage
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --acepta)  modo="acepta";  shift ;;
      --rechaza) modo="rechaza"; shift ;;
      --comentario)
        [ $# -ge 2 ] || die "--comentario requiere un texto"
        comentario="$2"
        shift 2
        ;;
      *) usage ;;
    esac
  done

  case "$numero" in
    ''|*[!0-9]*) die "intake requiere un numero de Issue: '$numero' no es un numero" ;;
  esac
  case "$modo" in
    acepta|rechaza) ;;
    *) die "intake requiere un veredicto: --acepta o --rechaza" ;;
  esac
  [ "$modo" != "rechaza" ] || [ -n "$comentario" ] \
    || die "intake --rechaza requiere --comentario \"<texto>\" — el veredicto del intake-reviewer es lo que se comenta en el Issue"

  require_cmd gh

  # Exactamente un borrador. Cero es un error de uso (nadie sincronizo ese Issue,
  # o ya se resolvio); mas de uno significa que hay dos sync de dias distintos
  # sin resolver y elegir por adivinanza seria peor que parar.
  [ -d "$AGENT_DIR/specs" ] \
    || die "no hay borrador para el issue #$numero en $AGENT_DIR/specs — corre task.sh sync antes de intake"
  borrador="$(find "$AGENT_DIR/specs" -maxdepth 1 -type f \
    -name "*-issue-${numero}-DRAFT.md" 2>/dev/null | LC_ALL=C sort)"
  conteo="$(printf '%s' "$borrador" | grep -c . || true)"
  [ "$conteo" -ne 0 ] \
    || die "no hay borrador para el issue #$numero en $AGENT_DIR/specs — corre task.sh sync antes de intake"
  [ "$conteo" -eq 1 ] \
    || die "hay mas de un borrador para el issue #$numero en $AGENT_DIR/specs — deja solo el que corresponde y vuelve a correr intake"

  if [ "$modo" = "acepta" ]; then
    # Primero GitHub, despues el disco: si la label no se pudo aplicar, el
    # borrador se queda tal cual. Al reves quedaria un estado a medias donde el
    # spec local dice "aceptado" y el proximo sync vuelve a traer el mismo Issue.
    gh issue edit "$numero" --add-label harness:synced >/dev/null 2>&1 \
      || die "no se pudo aplicar la label harness:synced al issue #$numero — revisa la sesion de gh y que el issue exista; el borrador se queda como estaba"
    mv "$borrador" "${borrador%-DRAFT.md}.md" \
      || die "no se pudo renombrar $borrador — la label harness:synced ya quedo aplicada al issue #$numero, retirala o renombra el archivo a mano"
    append_history intake "" "$(jq -n --arg n "$numero" '{issue: ($n | tonumber), veredicto: "acepta"}')"
    printf 'harness: issue #%s aceptado — %s es ahora el spec\n' "$numero" "${borrador%-DRAFT.md}.md"
    return 0
  fi

  gh issue comment "$numero" --body "$comentario" >/dev/null 2>&1 \
    || die "no se pudo comentar en el issue #$numero — revisa la sesion de gh y que el issue exista; el borrador se queda como estaba"
  gh issue edit "$numero" --add-label harness:needs-info >/dev/null 2>&1 \
    || die "no se pudo aplicar la label harness:needs-info al issue #$numero — el comentario ya quedo publicado; el borrador se queda como estaba"
  rm -f "$borrador"
  append_history intake "" "$(jq -n --arg n "$numero" '{issue: ($n | tonumber), veredicto: "rechaza"}')"
  printf 'harness: issue #%s devuelto por falta de informacion — borrador %s descartado\n' "$numero" "$borrador"
}

main() {
  [ $# -gt 0 ] || usage
  # Se comprueba antes de decidir el subcomando: un config con schema desconocido
  # rompe TODO subcomando de la misma manera, y responder distinto por caso solo
  # confunde el diagnostico. La comprobacion se hace aqui — no en _require_tasks_file —
  # porque cmd_list hace subshells de task_attested que se comerian el die() sin ruido,
  # y "config con schema no soportado" no es un fallo silenciable.
  _require_config_schema
  local subcommand="$1"
  shift
  case "$subcommand" in
    list)           cmd_list ;;
    show)           cmd_show "$@" ;;
    start)          cmd_start "$@" ;;
    start-worktree) cmd_start_worktree "$@" ;;
    implemented)    cmd_implemented "$@" ;;
    verify)      cmd_verify "$@" ;;
    merged)      cmd_merged "$@" ;;
    attest)      cmd_attest "$@" ;;
    review)      cmd_review "$@" ;;
    sync)        cmd_sync ;;
    intake)      cmd_intake "$@" ;;
    *)           die "subcomando desconocido: $subcommand" ;;
  esac
}

main "$@"
