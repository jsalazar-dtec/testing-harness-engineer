#!/usr/bin/env bash
# Que rol sigue, y con que artefactos. No invoca ningun agente: eso lo hace la
# sesion principal. El punto es exactamente ese: un contrato de handoff que
# vive en un archivo es testeable; uno que vive en una instruccion depende de
# que alguien se acuerde.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/state.sh
. "$HERE/lib/state.sh"

usage() {
  cat >&2 <<'TXT'
uso: pipeline.sh <subcomando>

  next        dice que rol sigue, con que tarea y que artefactos
  parallel    lista tareas pending y desbloqueadas — candidatas a worktrees paralelas
  state <id>  dice en que parte del pipeline esta una tarea
TXT
  exit "$EXIT_USAGE"
}

# --- localizar artefactos en .agent/ ----------------------------------------

_task_ids() {
  jq -r '.tasks[].id' "$(tasks_file)"
}

# El ultimo .md por orden lexicografico: los specs se nombran <fecha>-<slug>.md,
# asi que el orden lexicografico es el orden cronologico. Este harness trabaja
# una intencion a la vez, asi que "el spec" es el mas reciente.
_spec_file() {
  local f
  [ -d "$AGENT_DIR/specs" ] || return 1
  # Un *-DRAFT.md no es un spec: es un Issue esperando triage. Si contara,
  # _no_specs daria falso sin que exista ningun spec real y planner recibiria
  # como spec un borrador que nadie aprobo.
  f="$(find "$AGENT_DIR/specs" -maxdepth 1 -type f -name '*.md' ! -name '*-DRAFT.md' 2>/dev/null | LC_ALL=C sort | tail -1)"
  [ -n "$f" ] || return 1
  printf '%s' "$f"
}

_no_specs() {
  ! _spec_file >/dev/null 2>&1
}

# El *-DRAFT.md mas antiguo: primero por fecha (el nombre la lleva como prefijo
# YYYY-MM-DD, que ya ordena bien como texto), y dentro del mismo dia por el
# numero de Issue tratado como numero — no como texto, porque un sort de texto
# pone "issue-10" antes de "issue-9" ('1' < '9' como caracteres) justo cuando
# aparece un Issue de dos digitos el mismo dia que uno de un digito.
_draft_issue_file() {
  local f
  [ -d "$AGENT_DIR/specs" ] || return 1
  # El -name exige el patron completo '*-issue-<N>-DRAFT.md': un borrador escrito
  # a mano sin '-issue-<N>-' no da numero que ordenar y podria colarse primero.
  f="$(find "$AGENT_DIR/specs" -maxdepth 1 -type f -name '*-issue-*-DRAFT.md' 2>/dev/null \
    | while IFS= read -r path; do
        local base fecha resto numero
        base="$(basename "$path")"
        fecha="${base%%-issue-*}"
        resto="${base#*-issue-}"
        numero="${resto%%-DRAFT.md}"
        printf '%s\t%s\t%s\n' "$fecha" "$numero" "$path"
      done \
    | LC_ALL=C sort -t "$(printf '\t')" -k1,1 -k2,2n \
    | head -1 \
    | cut -f3-)"
  [ -n "$f" ] || return 1
  printf '%s' "$f"
}

# El directorio, no un archivo: puede haber varios catalogos de contratos y
# ningun campo en tasks.json dice cual le corresponde a cual tarea. Ese vacio
# de datos queda anotado en el reporte de esta tarea, no resuelto aqui con una
# adivinanza.
_acceptance_dir() {
  local dir="$AGENT_DIR/acceptance"
  [ -d "$dir" ] || return 1
  find "$dir" -maxdepth 1 -type f -name '*.json' 2>/dev/null | grep -q . || return 1
  printf '%s' "$dir"
}

# La vara con la que implementer escribe y reviewer juzga. Si no esta, ninguno
# de los dos falla: el implementer leeria un path que no existe y el reviewer
# juzgaria sin rubrica, en silencio. Por eso esta funcion, a diferencia de
# _spec_file o _acceptance_dir, no se limita a devolver 1 cuando falta: quien
# la llama tiene que avisar por stderr.
_guidelines_dir() {
  local dir="$AGENT_DIR/guidelines"
  [ -d "$dir" ] || return 1
  printf '%s/' "$dir"
}

_report_path() {
  local id="$1" sha
  sha="$(task_field "$id" verifiedAt)" || return 1
  printf '%s/reports/%s-%s.json' "$AGENT_DIR" "$sha" "$id"
}

# --- artefactos por rol -------------------------------------------------------
#
# Esta es la unica funcion que decide que ve cada rol. De aqui sale la garantia
# de aislamiento: reviewer no recibe tasks.json ni el reporte de quien
# implemento, y business-reviewer no recibe tasks.json. Ninguno de los dos
# tiene Write ni Edit — ninguno de los dos puede dejar un rastro propio en
# disco — asi que esta funcion es tambien el unico lugar donde se podria
# filtrar ese aislamiento por accidente.
role_artifacts() {
  local role="$1" id="${2:-}" spec acceptance branch guidelines

  case "$role" in
    # Sin tasks.json, sin brief, sin ningun reporte: intake-reviewer juzga el
    # borrador solo, igual que business-reviewer juzga sin el razonamiento
    # de quien implemento.
    intake-reviewer)
      printf 'role=intake-reviewer\n'
      printf 'draft=%s\n' "$id"
      ;;

    spec)
      printf 'role=spec\n'
      ;;

    planner)
      printf 'role=planner\n'
      if spec="$(_spec_file)"; then printf 'spec=%s\n' "$spec"; fi
      if acceptance="$(_acceptance_dir)"; then printf 'acceptance=%s\n' "$acceptance"; fi
      ;;

    integrator-start)
      printf 'role=integrator\n'
      printf 'task=%s\n' "$id"
      printf 'action=start\n'
      printf 'brief=%s\n' "$(tasks_file)"
      ;;

    implementer)
      printf 'role=implementer\n'
      printf 'task=%s\n' "$id"
      printf 'brief=%s\n' "$(tasks_file)"
      if spec="$(_spec_file)"; then printf 'spec=%s\n' "$spec"; fi
      if acceptance="$(_acceptance_dir)"; then printf 'acceptance=%s\n' "$acceptance"; fi
      if guidelines="$(_guidelines_dir)"; then
        printf 'guidelines=%s\n' "$guidelines"
      else
        printf 'harness: no existe %s/guidelines/ — el implementer va a escribir sin rubrica\n' "$AGENT_DIR" >&2
      fi
      ;;

    # Sin brief (tasks.json) y sin ningun campo de reporte o razonamiento del
    # implementador: reviewer juzga el diff y el spec, no las afirmaciones de
    # quien lo escribio.
    reviewer)
      printf 'role=reviewer\n'
      printf 'task=%s\n' "$id"
      if branch="$(task_field "$id" branch 2>/dev/null)"; then
        printf 'branch=%s\n' "$branch"
      fi
      if spec="$(_spec_file)"; then printf 'spec=%s\n' "$spec"; fi
      if guidelines="$(_guidelines_dir)"; then
        printf 'guidelines=%s\n' "$guidelines"
      else
        printf 'harness: no existe %s/guidelines/ — el reviewer va a juzgar sin rubrica\n' "$AGENT_DIR" >&2
      fi
      ;;

    # Sin brief (tasks.json): business-reviewer juzga contra el spec y los
    # contratos, nunca contra el razonamiento de quien planifico ni de quien
    # implemento.
    business-reviewer)
      printf 'role=business-reviewer\n'
      printf 'task=%s\n' "$id"
      if branch="$(task_field "$id" branch 2>/dev/null)"; then
        printf 'branch=%s\n' "$branch"
      fi
      if spec="$(_spec_file)"; then printf 'spec=%s\n' "$spec"; fi
      if acceptance="$(_acceptance_dir)"; then printf 'acceptance=%s\n' "$acceptance"; fi
      ;;

    # Sin brief y sin ningun artefacto de las dos revisiones: verifier corre los
    # gates y deja que ellos decidan, no relee lo que reviewer y business-reviewer
    # ya aprobaron.
    verifier)
      printf 'role=verifier\n'
      printf 'task=%s\n' "$id"
      ;;

    integrator-pr)
      printf 'role=integrator\n'
      printf 'task=%s\n' "$id"
      printf 'action=open-pr\n'
      printf 'brief=%s\n' "$(tasks_file)"
      if spec="$(_spec_file)"; then printf 'spec=%s\n' "$spec"; fi
      # El reporte de verify.sh, no el del implementador: es evidencia de gates,
      # no una afirmacion sin verificar. El integrator lo necesita para que un
      # revisor humano pueda verlo en el diff del PR.
      _report_path "$id" 2>/dev/null | { read -r r && [ -n "$r" ] && printf 'report=%s\n' "$r"; } || true
      ;;

    *)
      printf 'harness: rol desconocido: %s\n' "$role" >&2
      return 1
      ;;
  esac
}

# --- next --------------------------------------------------------------------

cmd_next() {
  local id status blockers motivo blocked_msgs="" draft

  # 1) Un verified sin atestacion que se sostenga es un alto duro para todo el
  #    pipeline, no solo para esa tarea: se comprueba primero y, si falla, no
  #    se ofrece ningun otro rol.
  for id in $(_task_ids); do
    status="$(task_status "$id")" || continue
    [ "$status" = "verified" ] || continue
    if ! motivo="$(task_attested "$id")"; then
      printf 'harness: %s\n' "$motivo" >&2
      printf 'harness: %s esta verified pero su atestacion no se sostiene — no se avanza\n' "$id" >&2
      exit "$EXIT_GATE"
    fi
    role_artifacts integrator-pr "$id"
    return 0
  done

  # 2) Tareas implementadas: la secuencia reviewer -> business-reviewer -> verifier
  #    se lee de reviews, no de la memoria de la sesion orquestadora. Ninguno de los
  #    dos revisores tiene Write, asi que este campo es lo unico que hace que "ya
  #    revise esto" sobreviva entre invocaciones de pipeline.sh.
  for id in $(_task_ids); do
    status="$(task_status "$id")" || continue
    [ "$status" = "implemented" ] || continue

    local tecnico negocio
    tecnico="$(task_review "$id" tecnico)" || tecnico=""
    negocio="$(task_review "$id" negocio)" || negocio=""

    # Un rojo bloquea aunque el otro gate haya aprobado — los dos revisores son
    # independientes y no hay arbitro, la misma regla que verify.sh aplica a lint,
    # tests y coverage.
    if [ "$tecnico" = "rechaza" ]; then
      printf 'harness: %s rechazada por el reviewer (tecnico) — no se avanza\n' "$id" >&2
      exit "$EXIT_GATE"
    fi
    if [ "$negocio" = "rechaza" ]; then
      printf 'harness: %s rechazada por el business-reviewer (negocio) — no se avanza\n' "$id" >&2
      exit "$EXIT_GATE"
    fi

    if [ "$tecnico" = "ok" ] && [ "$negocio" = "ok" ]; then
      role_artifacts verifier "$id"
      return 0
    fi
    if [ "$tecnico" = "ok" ]; then
      role_artifacts business-reviewer "$id"
      return 0
    fi
    role_artifacts reviewer "$id"
    return 0
  done

  # 3) Tareas pendientes y desbloqueadas.
  for id in $(_task_ids); do
    status="$(task_status "$id")" || continue
    [ "$status" = "pending" ] || continue
    if blockers="$(task_blockers "$id")"; then
      if task_field "$id" branch >/dev/null 2>&1; then
        role_artifacts implementer "$id"
      else
        role_artifacts integrator-start "$id"
      fi
      return 0
    fi
    # task_blockers puede fallar por dos motivos: hay bloqueantes (stdout con la
    # lista), o una dependencia no existe (ya murio por stderr con su propio
    # mensaje y stdout vacio). En el segundo caso no hay nada que añadir aqui.
    [ -n "$blockers" ] || exit "$EXIT_USAGE"
    blocked_msgs="${blocked_msgs}harness: $id bloqueada por: $(printf '%s' "$blockers" | tr '\n' ' ' | sed 's/ $//')
"
  done

  # 4) Un Issue esperando triage bloquea escribir un spec nuevo desde cero, pero
  #    no bloquea el trabajo ya en vuelo: se comprueba en el mismo lugar de
  #    prioridad que "no hay spec", despues del barrido de tareas. Ponerlo antes
  #    de todo dejaba el pipeline sin poder avanzar ninguna tarea desde el primer
  #    sync hasta que alguien resolviera el borrador.
  if draft="$(_draft_issue_file)"; then
    role_artifacts intake-reviewer "$draft"
    return 0
  fi

  # 5) Sin spec no hay nada que descomponer.
  if _no_specs; then
    printf 'role=spec\n'
    printf 'motivo=no hay spec en %s/specs\n' "$AGENT_DIR"
    return 0
  fi

  # 6) Hay spec y ninguna tarea todavia.
  if [ "$(task_count)" -eq 0 ]; then
    role_artifacts planner ""
    return 0
  fi

  if [ -n "$blocked_msgs" ]; then
    printf '%s' "$blocked_msgs" >&2
    printf 'harness: nada accionable — todo lo pendiente esta bloqueado\n' >&2
    exit "$EXIT_USAGE"
  fi

  printf 'harness: nada accionable — no hay tareas que avanzar (todas merged o no hay tareas)\n' >&2
  exit "$EXIT_USAGE"
}

# --- parallel ------------------------------------------------------------
#
# Lista las tareas que estan pending, desbloqueadas y sin rama asignada. Son
# candidatas legitimas a trabajarse en paralelo, cada una en su propio git
# worktree. No es un despachador — no crea worktrees, no asigna trabajo — es
# una respuesta a "que puedo abrir en paralelo sin pisar nada".
#
# Convivencia con next: next devuelve UNA sola cosa (la de mayor prioridad),
# parallel devuelve TODAS las que caben a la vez. Un pipeline serio corre next
# para saber que urge y parallel para saber que mas puede avanzar en paralelo.
cmd_parallel() {
  local id status blockers vistas=0
  for id in $(_task_ids); do
    status="$(task_status "$id")" || continue
    [ "$status" = "pending" ] || continue
    # Con rama ya asignada, la tarea ya arranco: no es candidata a un worktree
    # nuevo aunque este pending, porque el trabajo empezo en la rama que ya
    # tiene registrada.
    if task_field "$id" branch >/dev/null 2>&1; then
      continue
    fi
    if blockers="$(task_blockers "$id")"; then
      printf 'task=%s\n' "$id"
      printf 'worktree=.worktrees/%s\n' "$id"
      printf 'branch-hint=feat/%s-<slug>\n\n' "$id"
      vistas=$((vistas + 1))
    else
      [ -n "$blockers" ] || continue
    fi
  done
  if [ "$vistas" -eq 0 ]; then
    printf 'harness: ninguna tarea pending y desbloqueada — nada que abrir en paralelo\n' >&2
    exit "$EXIT_USAGE"
  fi
  printf 'harness: %d tarea(s) candidatas — cada una en su propio git worktree bajo .worktrees/\n' \
    "$vistas" >&2
  printf 'harness: para arrancar una: ./scripts/task.sh start-worktree <id>\n' >&2
}

# --- state ---------------------------------------------------------------

cmd_state() {
  local id="${1:-}" status blockers motivo
  [ -n "$id" ] || usage
  status="$(task_status "$id")" || die "tarea desconocida: $id"
  printf 'task=%s\n' "$id"
  printf 'status=%s\n' "$status"
  case "$status" in
    pending)
      if blockers="$(task_blockers "$id")"; then
        printf 'blocked=no\n'
      else
        [ -n "$blockers" ] || exit "$EXIT_USAGE"
        printf 'blocked=si\n'
        printf 'blockers=%s\n' "$(printf '%s' "$blockers" | tr '\n' ',' | sed 's/,$//')"
      fi
      ;;
    verified|merged)
      if motivo="$(task_attested "$id")"; then
        printf 'attested=si\n'
      else
        printf 'attested=no\n'
        printf 'motivo=%s\n' "$motivo"
      fi
      ;;
  esac
}

main() {
  [ $# -gt 0 ] || usage
  # Ver el mismo comentario en task.sh: un schema desconocido rompe todo por igual.
  _require_config_schema
  local subcommand="$1"
  shift
  case "$subcommand" in
    next)     cmd_next "$@" ;;
    parallel) cmd_parallel "$@" ;;
    state)    cmd_state "$@" ;;
    *)        die "subcomando desconocido: $subcommand" ;;
  esac
}

# Permite sourcear este archivo para usar role_artifacts directamente (asi lo
# hacen los tests de aislamiento) sin disparar main con argv vacio.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
