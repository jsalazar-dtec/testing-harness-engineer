#!/usr/bin/env bash
# Diagnostico del entorno del harness. No arregla nada — dice que falta y por
# que, con exit code util:
#
#   0  todo lo esperado esta presente
#   1  falta algo blocking (jq, git, config invalido)
#   2  hay warnings (gtimeout ausente en macOS, workflow sin jobs esperados)
#
# Idempotente: leelo tantas veces como quieras, no toca disco.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
AGENT_DIR="$ROOT/.agent"
CONFIG="$AGENT_DIR/config.json"

RC_OK=0
RC_MISS=1
RC_WARN=2

status=$RC_OK
ok()   { printf 'harness: [ok]   %s\n' "$1"; }
warn() { printf 'harness: [warn] %s\n' "$1" >&2; [ "$status" -lt "$RC_WARN" ] && status=$RC_WARN || :; }
bad()  { printf 'harness: [bad]  %s\n' "$1" >&2; status=$RC_MISS; }

# --- comandos requeridos ------------------------------------------------------

for cmd in jq git; do
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$cmd presente"
  else
    bad "falta $cmd — el harness no funciona sin el"
  fi
done

for cmd in gh bats python3; do
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$cmd presente"
  else
    warn "$cmd ausente — degrada funciones (gh: sync/intake/actions gate; bats: correr tests; python3: reconstruir Edits parciales en protect_artifacts)"
  fi
done

# macOS no trae timeout; coreutils lo instala como gtimeout. Sin el, cheap_loop
# y verify.sh corren sin limite: un test o lint que cuelga cuelga la sesion.
if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
  ok "timeout o gtimeout presente"
else
  warn "sin timeout ni gtimeout — instala coreutils (brew install coreutils en macOS) para que los gates puedan cortarse"
fi

# --- repo git y ubicacion -----------------------------------------------------

if git -C "$ROOT" rev-parse --show-toplevel >/dev/null 2>&1; then
  ok "$ROOT es un repo git"
else
  bad "$ROOT no es un repo git — corre 'git init' o scripts/bootstrap.sh"
fi

# --- config.json --------------------------------------------------------------

if [ ! -f "$CONFIG" ]; then
  bad "no existe $CONFIG — corre scripts/bootstrap.sh"
elif ! jq -e . "$CONFIG" >/dev/null 2>&1; then
  bad "$CONFIG no es JSON valido"
else
  schema="$(jq -r '."$schema" // ""' "$CONFIG")"
  if [ "$schema" = "harness/1" ]; then
    ok "config \$schema = harness/1"
  elif [ -z "$schema" ]; then
    bad "config no declara \$schema — corre scripts/bootstrap.sh para migrarlo"
  else
    bad "config declara \$schema = $schema — este harness solo entiende harness/1"
  fi

  stack="$(jq -r '.stack // ""' "$CONFIG")"
  case "$stack" in
    ""|null|unknown) bad "config.stack sin definir — planner y implementer lo necesitan" ;;
    *)               ok "config.stack = $stack" ;;
  esac

  for clave in lint test coverage testRelated; do
    valor="$(jq -r --arg k "$clave" '.commands[$k] // ""' "$CONFIG")"
    case "$valor" in
      ""|null) warn "config.commands.$clave sin definir — este gate quedara skipped en cada verify" ;;
      *)       ok "config.commands.$clave definido" ;;
    esac
  done
fi

# --- workflow de CI que reviewer espera ---------------------------------------

if [ -d "$ROOT/.github/workflows" ]; then
  faltan=""
  for job in tests coverage dependencias secretos; do
    if ! grep -R -l -E "^\s*(name:\s*)?$job\s*:?" "$ROOT/.github/workflows" >/dev/null 2>&1 \
       && ! grep -R -l -E "^\s+$job:" "$ROOT/.github/workflows" >/dev/null 2>&1; then
      faltan="$faltan $job"
    fi
  done
  if [ -z "$faltan" ]; then
    ok "workflows de GitHub Actions declaran tests, coverage, dependencias, secretos"
  else
    warn "workflows sin jobs con los nombres que reviewer busca:$faltan (o los estas nombrando distinto — reviewer va a decir 'no vi ese job')"
  fi
else
  warn "no hay $ROOT/.github/workflows — sin CI reviewer va a reportar 'no hay run para ese commit'"
fi

# --- init.sh ------------------------------------------------------------------

if [ -x "$AGENT_DIR/init.sh" ]; then
  if grep -q "sin configurar\|sin comandos concretos" "$AGENT_DIR/init.sh" 2>/dev/null; then
    warn ".agent/init.sh es un placeholder — anadele los comandos reales para levantar el proyecto"
  else
    ok ".agent/init.sh definido"
  fi
else
  bad ".agent/init.sh no existe o no es ejecutable"
fi

# --- drift template <-> proyecto ----------------------------------------------
#
# Sin baseline commiteado del template original en el proyecto no se puede
# medir drift. Se reporta como nota, no como warn: es informacion util para
# decidir cuando pull nuevas versiones del harness.

if [ -f "$AGENT_DIR/.harness-baseline" ]; then
  ok "baseline del harness registrado en $AGENT_DIR/.harness-baseline"
else
  printf 'harness: [info] no hay .agent/.harness-baseline — sin baseline no se puede medir drift entre este proyecto y el template original\n'
fi

exit "$status"
