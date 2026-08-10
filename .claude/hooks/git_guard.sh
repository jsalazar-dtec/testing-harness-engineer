#!/usr/bin/env bash
# PreToolUse sobre Bash: impide integrar directamente en ramas protegidas.
# Falla abierto a propósito: ante cualquier duda deja pasar. Su cobertura de tests
# es lo único que garantiza que siga protegiendo.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/lib/git_flow.sh
. "$HERE/../../scripts/lib/git_flow.sh" 2>/dev/null || exit 0
# shellcheck source=../../scripts/lib/cmdscan.sh
. "$HERE/../../scripts/lib/cmdscan.sh" 2>/dev/null || exit 0

command -v jq >/dev/null 2>&1 || exit 0

payload="$(cat)"
cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[ -n "$cmd" ] || exit 0

# Solo nos importan los verbos que integran, y el verbo tiene que venir justo
# tras "git" para que un mensaje de commit que mencione "push" no dispare el guard.
#
# El comando se evalua por segmentos porque un agente escribe
# "git add -A && git commit -m x" mucho mas a menudo que "git commit" a secas.
# Anclar el patron al comando completo dejaba pasar eso sin examinarlo, y eso no
# es fallar abierto ante una duda: es no reconocer que el comando era git.
#
# cmd_segments parte por los separadores que estan FUERA de comillas, asi que un
# echo "texto && git commit -m x" queda en un solo segmento y no se confunde con un
# commit: seria un falso positivo que ademas falla cerrado, justo al contrario de lo
# que este hook promete.
#
# El verbo se lee con cmd_verb (primera palabra, comillas QUITADAS) y el subverbo de
# las palabras, tambien sin comillas. Con las comillas vaciadas, `git "commit" -m x`
# se leia como `git ""` y esquivaba el guard ejecutando exactamente un commit.

integrates=0
while IFS= read -r segment; do
  [ "$(cmd_verb "$segment")" = "git" ] || continue
  visto=0
  while IFS= read -r word; do
    if [ "$visto" -eq 0 ]; then
      case "${word##*/}" in git) visto=1 ;; esac
      continue
    fi
    # Las opciones globales se saltan; el primer no-flag es el subcomando. Limitacion
    # conocida y aceptada: `git -C /otro/repo commit` toma /otro/repo como subcomando
    # y no se detecta. Cubrirlo exige parsear las opciones globales de git, y este
    # script tiene que seguir siendo auditable de una lectura. Cae del lado fail-open.
    case "$word" in -*) continue ;; esac
    case "$word" in
      commit|merge|push|rebase) integrates=1 ;;
    esac
    break
  done <<PALABRAS
$(cmd_words "$segment")
PALABRAS
  [ "$integrates" -eq 1 ] && break
done <<SEGMENTOS
$(cmd_segments "$cmd")
SEGMENTOS

# El bucle va con heredoc y no con pipe a proposito: por un pipe correria en una
# subshell y el valor de integrates se perderia al terminar.
[ "$integrates" -eq 1 ] || exit 0

branch="$(current_branch)" || exit 0
[ -n "$branch" ] && [ "$branch" != "HEAD" ] || exit 0

if is_protected_branch "$branch"; then
  printf 'harness: %s es una rama protegida — trabaja en una rama efimera (feat/, fix/, chore/) y abre un PR\n' \
    "$branch" >&2
  exit 2
fi

exit 0
