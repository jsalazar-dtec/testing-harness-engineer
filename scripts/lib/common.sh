#!/usr/bin/env bash
# Utilidades compartidas por todos los scripts del harness.
# Idempotente al sourcearse: las constantes son readonly y redeclararlas aborta.

[ -n "${HARNESS_COMMON_LOADED:-}" ] && return 0
HARNESS_COMMON_LOADED=1

readonly EXIT_OK=0
readonly EXIT_USAGE=1
readonly EXIT_GUARD=2
readonly EXIT_GATE=3

die() {
  printf 'harness: %s\n' "$1" >&2
  exit "${2:-$EXIT_USAGE}"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "falta el comando requerido: $1"
}
