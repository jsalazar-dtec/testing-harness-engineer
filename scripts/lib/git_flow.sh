#!/usr/bin/env bash
# Detección de topología de ramas. La rama de integración se detecta, nunca se asume:
# en repos distintos se llama develop, development o dev, y algunos no tienen ninguna.

[ -n "${HARNESS_GIT_FLOW_LOADED:-}" ] && return 0
HARNESS_GIT_FLOW_LOADED=1

# shellcheck source=./common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

current_branch() {
  git rev-parse --abbrev-ref HEAD 2>/dev/null
}

_branch_exists() {
  git show-ref --verify --quiet "refs/heads/$1" && return 0
  git show-ref --verify --quiet "refs/remotes/origin/$1" && return 0
  return 1
}

detect_integration_branch() {
  local candidate config configured
  # Un proyecto puede llamar a su rama de integracion "trunk", "integration"
  # o "staging" — nombres fuera del abanico develop/development/dev. Antes de
  # adivinar, se lee integrationBranch de .agent/config.json: es un campo del
  # schema que existia sin consumidor. Un valor null se ignora (fallback al
  # abanico); un valor con nombre que no existe como rama se rechaza en vez de
  # asumir, porque asumir es un bug.
  config="${AGENT_DIR:-.agent}/config.json"
  if [ -f "$config" ] && command -v jq >/dev/null 2>&1; then
    configured="$(jq -r '.integrationBranch // ""' "$config" 2>/dev/null)"
    if [ -n "$configured" ] && [ "$configured" != "null" ]; then
      if _branch_exists "$configured"; then
        printf '%s' "$configured"
        return 0
      fi
      # El config declara una rama que git no encuentra. No hay adivinanza aceptable:
      # que el integrator diga en su reporte que hace falta arreglar el config.
      printf 'harness: config.integrationBranch=%s no existe como rama — corrigelo en .agent/config.json\n' \
        "$configured" >&2
      return 1
    fi
  fi
  for candidate in develop development dev; do
    if _branch_exists "$candidate"; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

is_protected_branch() {
  # `${1:-}` y no `$1`: los hooks corren con `set -u` y una llamada sin argumento
  # moria con "unbound variable" en vez de responder. Esta funcion es la dependencia
  # del hook que falla ABIERTO, asi que un error aqui se traduce en dejar pasar.
  local branch="${1:-}" integration
  [ -n "$branch" ] || return 1
  case "$branch" in
    main|master|qa|uat) return 0 ;;
  esac
  integration="$(detect_integration_branch)" || return 1
  [ "$branch" = "$integration" ]
}
