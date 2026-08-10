#!/usr/bin/env bash
# PreToolUse sobre Edit, Write y Bash: protege los artefactos que el harness no puede
# permitirse perder. Falla CERRADO, al contrario que git_guard.sh: un commit
# bloqueado por error se reintenta; unos contratos borrados, no.
#
# Fallar cerrado no significa una sola salida limpia: hay cuatro (el fin de la rama
# Bash, la ruta no protegida, la clase harness con sello, y el final). El invariante
# real es mas estrecho: no hay ninguna salida limpia SIN sello sobre una ruta
# protegida. A partir de ahi, cualquier duda bloquea.
set -uo pipefail

block() {
  printf 'harness: %s\n' "$1" >&2
  exit 2
}

command -v jq >/dev/null 2>&1 || block "falta jq y este hook no puede verificar nada"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/lib/cmdscan.sh
. "$HERE/../../scripts/lib/cmdscan.sh" 2>/dev/null \
  || block "no se pudo cargar cmdscan.sh — un guard que no puede clasificar rutas no deja pasar nada"

payload="$(cat)"

tool="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)"

if [ "$tool" = "Bash" ]; then
  cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)" \
    || block "no se pudo leer el comando"

  # TODO el analisis va por segmento, y el flag se recalcula en cada uno. Cuando el
  # verbo se leia del comando completo y los flags no se reseteaban, la cobertura era
  # a la vez demasiado ancha y asimetrica: `rm -rf dist/ && npm test` se bloqueaba
  # para siempre (la palabra suelta "test" caia en la rama de rm) mientras que
  # `cat test/foo.spec.ts && mv a b` pasaba y `mv a b && cat test/foo.spec.ts` no.
  # Un guard que bloquea trabajo legitimo se desinstala, y con el se pierde todo lo
  # demas que protege.
  #
  # El verbo sale de cmd_verb (primera palabra, comillas QUITADAS) y no de vaciar las
  # comillas: `"mv" /tmp/x .agent/tasks.json` y `m"v" ...` se ejecutan igual que sin
  # comillas y tienen que contar igual. Las rutas salen de cmd_words, tambien con las
  # comillas quitadas, porque vaciarlas perderia justo el argumento que interesa.
  #
  # Limites conocidos y aceptados, documentados aqui a proposito: un comando que
  # CALCULA la ruta, un `python -c`, un `find | xargs rm` que recibe las rutas por
  # stdin, o un prefijo de asignacion (`VAR=1 mv a b`) escapan a este detector. Este
  # hook bloquea patrones, no computacion arbitraria. La defensa final es el diff del
  # PR y no conceder Bash sin restringir.
  while IFS= read -r segment; do
    [ -n "$segment" ] || continue
    verbo="$(cmd_verb "$segment")"

    borra=0
    escribe=0
    muta=0
    git_verbo=""
    # Los refs y las rutas son ambiguos en checkout/restore/switch: `git checkout -b
    # feat/T1-agrega-tests` no toca ningun archivo y bloquearlo seria sobre-bloqueo de
    # un comando cotidiano. Para esos tres se exige que la palabra exista en disco;
    # para rm, clean y stash no hace falta, porque solo aceptan rutas.
    solo_existentes=0

    case "$verbo" in
      rm)
        borra=1
        ;;
      mv|cp|tee|install|truncate|dd|ln)
        escribe=1
        ;;
    esac

    case "$segment" in
      chmod\ *|*/chmod\ *|chown\ *|*/chown\ *|chflags\ *|xattr\ *) muta=1 ;;
    esac

    case "$verbo" in
      sed)
        # El plan pide las dos formas. El codigo habia perdido --in-place, y
        # `sed --in-place s/implemented/verified/ .agent/tasks.json` pasaba entero.
        while IFS= read -r word; do
          case "$word" in
            -i|-i*|--in-place|--in-place=*) escribe=1 ;;
          esac
        done <<SEDFLAGS
$(cmd_words "$segment")
SEDFLAGS
        ;;
      git)
        # git es una ruta completa a verified sin tocar ningun hook de Edit/Write:
        # `git rm -f .agent/tasks.json` seguido de un Write con la tarea ya en
        # verified. Borrar con git destruye igual que borrar con rm.
        visto=0
        while IFS= read -r word; do
          if [ "$visto" -eq 0 ]; then
            case "${word##*/}" in git) visto=1 ;; esac
            continue
          fi
          case "$word" in -*) continue ;; esac
          git_verbo="$word"
          break
        done <<GITVERB
$(cmd_words "$segment")
GITVERB
        case "$git_verbo" in
          rm|clean|stash)        borra=1 ;;
          checkout|restore|switch) borra=1; solo_existentes=1 ;;
          *)                     git_verbo="" ;;
        esac
        ;;
    esac

    # Estos alcanzan el arbol entero, asi que alcanzan los artefactos protegidos sin
    # nombrarlos. No hay ruta que escanear: se bloquean por lo que son.
    case "$segment" in
      git\ clean*|*/git\ clean*|git\ reset\ *--hard*|git\ stash|git\ stash\ *|git\ checkout\ .*|git\ restore\ .*|*/git\ restore\ .*|git\ checkout\ --\ .*|*/git\ checkout\ --\ .*)
        block "ese comando alcanza todo el arbol y con el los artefactos del harness — usa una ruta concreta"
        ;;
    esac

    if [ "$borra" -eq 1 ] || [ "$escribe" -eq 1 ] || [ "$muta" -eq 1 ]; then
      while IFS= read -r word; do
        case "$word" in -*|'>') continue ;; esac
        # rm -rf .agent/* nombra el directorio aunque el literal * no case ningun archivo.
        case "$word" in *'/*'|*'/'*'*') word="${word%/*}" ;; esac
        if [ "$solo_existentes" -eq 1 ] && [ ! -e "$word" ]; then
          continue
        fi
        if ! is_protected_path "$word" >/dev/null; then
          # is_protected_path no reconoce ".agent/acceptance" ni ".agent/reports" como
          # directorio en si (solo clasifica los .json que hay dentro), asi que un rm
          # -rf de la carpeta entera no caia en ningun patron. Se sube por los
          # prefijos de la ruta: cualquiera que is_protected_path clasifique como
          # agentdir (hoy solo ".agent" mismo) protege tambien lo que cuelga debajo.
          prefijo="$word"
          agentdir_prefijo=""
          while :; do
            case "$prefijo" in
              */*) prefijo="${prefijo%/*}" ;;
              *) break ;;
            esac
            agentdir_prefijo="$(is_protected_path "$prefijo" 2>/dev/null || true)"
            [ "$agentdir_prefijo" = "agentdir" ] && break
            agentdir_prefijo=""
          done
          [ -n "$agentdir_prefijo" ] || continue
        fi
        if [ -n "$git_verbo" ]; then
          block "git $git_verbo destruiria un artefacto protegido ($word) — borrar con git destruye igual que borrar con rm"
        elif [ "$borra" -eq 1 ]; then
          block "los tests y los artefactos de estado no se borran — si un caso ya no aplica, cambialo, no lo elimines ($word)"
        elif [ "$muta" -eq 1 ]; then
          block "no se pueden cambiar permisos o atributos de un artefacto protegido: $word"
        else
          block "no se puede sobrescribir un artefacto protegido: $word"
        fi
      done <<PALABRAS
$(cmd_words "$segment")
PALABRAS
    fi

    # De una redireccion solo interesa el DESTINO: el token que sigue a un > suelto.
    # Mirar cualquier mencion bloquearia un `npm test -- tests/x.spec.ts 2>/dev/null`,
    # que no escribe nada protegido. cmd_words ya separo los operadores.
    siguiente_es_destino=0
    while IFS= read -r word; do
      if [ "$siguiente_es_destino" -eq 1 ]; then
        siguiente_es_destino=0
        is_protected_path "$word" >/dev/null \
          && block "no se puede redirigir a un artefacto protegido: $word"
        continue
      fi
      [ "$word" = ">" ] && siguiente_es_destino=1
    done <<PALABRAS2
$(cmd_words "$segment")
PALABRAS2
  done <<SEGMENTOS
$(cmd_segments "$cmd")
SEGMENTOS

  # Un payload de Bash no trae archivo que validar: sabido que no borra ni sobrescribe
  # nada protegido, no queda nada mas que comprobar.
  exit 0
fi

path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)" \
  || block "no se pudo leer el payload del hook"
[ -n "$path" ] || block "el payload del hook no trae file_path"

protegido="$(is_protected_path "$path" || true)"

# Decidir la proteccion primero es lo que hace que este hook falle cerrado de
# verdad: una ruta que no protegemos no es asunto suyo y sale limpia aqui, y a
# partir de esta linea CUALQUIER duda bloquea.
[ -n "$protegido" ] || exit 0

# Las clases que no necesitan mirar el contenido se resuelven antes de intentar
# reconstruirlo, para que el mensaje diga la causa real y no "no se pudo determinar
# el contenido".
case "$protegido" in
  harness)
    # Ningun guard basado en hooks sobrevive a un agente con permiso de escritura
    # sobre si mismo, y eso es exactamente el punto: la promesa central de esta
    # plantilla es que el agente no puede declararse exitoso. Con cmdscan.sh
    # escribible bastaban dos escrituras — dejar is_protected_path retornando 1 y
    # luego marcar verified a mano — y los hooks releen el disco en cada invocacion,
    # asi que ni hace falta reiniciar la sesion. El guard se protege igual que
    # protege tasks.json, y por el mismo razonamiento.
    [ "${HARNESS_TASK_SH:-}" = "1" ] \
      || block "$path es parte del harness (hooks, su configuracion y los scripts que corren los gates) — no se modifica desde el agente; si el harness tiene un defecto, reportalo en el PR"
    exit 0
    ;;
  guidelines)
    # La rubrica la lee quien implementa y la aplica quien revisa. Escribible, deja de
    # ser una vara: basta con bajar la regla que estorba para que el diff cumpla. Ni
    # siquiera el sello de task.sh la abre, porque ningun script del harness la escribe
    # — la edita una persona, fuera del ciclo de agentes, y eso es el punto.
    block "$path es la rubrica con la que se juzga tu trabajo — no se edita desde el agente; si una regla estorba o esta mal, reportalo"
    ;;
  agentdir)
    block "$path es el directorio de estado del harness — no se escribe encima"
    ;;
esac

# Edit trae new_string; Write trae content. Un Edit parcial no permite validar el
# archivo completo, así que en ese caso se reconstruye aplicando el reemplazo.
content="$(printf '%s' "$payload" | jq -r '.tool_input.content // empty' 2>/dev/null)"
if [ -z "$content" ]; then
  old="$(printf '%s' "$payload" | jq -r '.tool_input.old_string // empty' 2>/dev/null)"
  new="$(printf '%s' "$payload" | jq -r '.tool_input.new_string // empty' 2>/dev/null)"
  if [ -n "$old" ] && [ -f "$path" ]; then
    # Sin python3 el hook seguia bloqueando, que es lo correcto, pero el mensaje era
    # "python3: command not found" y no decia ni que archivo ni por que. Fallar
    # cerrado sin explicarse deja al usuario sin nada que hacer.
    command -v python3 >/dev/null 2>&1 \
      || block "este hook necesita python3 para reconstruir el contenido propuesto de un Edit sobre $path, y no esta en el PATH — instala python3, o usa Write con el archivo completo"
    content="$(python3 - "$path" "$old" "$new" <<'PY'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as fh:
    sys.stdout.write(fh.read().replace(old, new, 1))
PY
)" || block "no se pudo reconstruir el contenido propuesto para $path"
  fi
fi

# jq no sustituye // empty sobre una cadena vacia: en jq solo null y false son
# falsos. Asi que un Write con content:"" llega aqui con content vacio de verdad,
# y salir con 0 vaciaria el archivo sin pasar por ninguna validacion. Vaciar es el
# caso mas extremo de bajar el conteo y de JSON invalido a la vez.
[ -n "$content" ] \
  || block "no se pudo determinar el contenido propuesto para $path — este archivo esta protegido y el guard no deja pasar lo que no puede verificar"

# NO llama a block() por dentro, y esa es toda la razon de que devuelva estado en
# vez de abortar: se consume dentro de $( ), y un exit 2 ahi solo mata la subshell.
# El hook seguia con la cuenta vacia, imprimia el mensaje de bloqueo y salia con 0
# — un guard que dice "bloqueado" y devuelve exito invalida cualquier auditoria por
# logs. Aqui se devuelve 1 y el llamador, que si esta en el shell principal, bloquea.
#
# `jq -e .` primero: valida que el contenido sea JSON antes de contar nada. Y la
# consulta pasa por `arrays`, no por `length` a secas, porque `null | length` da 0
# en jq: un tasks.json sin .tasks contaba 0 tareas y entraba como si fuera valido.
count_or_fail() {
  local json="$1" query="$2" n
  printf '%s' "$json" | jq -e . >/dev/null 2>&1 || return 1
  n="$(printf '%s' "$json" | jq -e "$query" 2>/dev/null)" || return 1
  [ -n "$n" ] || return 1
  printf '%s' "$n"
}

if [ "$protegido" = "tasks" ]; then
  nuevo="$(count_or_fail "$content" '.tasks | arrays | length')" \
    || block "JSON invalido en $path — se esperaba un objeto con la lista .tasks; el harness no acepta artefactos de estado corruptos"
  [ -n "$nuevo" ] \
    || block "JSON invalido en $path — no se pudo contar la lista .tasks"

  if [ -f "$path" ]; then
    actual="$(jq -e '.tasks | arrays | length' "$path" 2>/dev/null)" \
      || block "el tasks.json actual no tiene una lista .tasks valida"
    [ "$nuevo" -ge "$actual" ] \
      || block "el cambio baja el numero de tareas de $actual a $nuevo — las tareas no se borran"
  fi
  # La otra mitad de la ruta que abria `git rm`: borrar tasks.json y volver a
  # CREARLO con las tareas ya en verified o merged. Sin archivo previo no hay ningun
  # exito anterior, asi que cualquier exito del contenido nuevo es nuevo y necesita
  # el sello.

  if [ "${HARNESS_TASK_SH:-}" != "1" ]; then
    # Se comparan los CONJUNTOS de ids en verified Y en merged, no sus tamanos. Con
    # el conteo bastaba bajar una tarea ya verificada a implemented y subir otra a
    # verified en la misma escritura: el total no cambiaba y el sello fraudulento
    # entraba. merged es el otro estado terminal de exito — tambien desbloquea
    # dependencias — y un Write directo no pasa por state.sh, asi que no basta con
    # mirar verified.
    for estado_exito in verified merged; do
      antes_ids="$(jq -r --arg e "$estado_exito" \
        '[.tasks[] | select(.status == $e) | .id] | sort | .[]' "$path" 2>/dev/null)"
      despues_ids="$(printf '%s' "$content" | jq -r --arg e "$estado_exito" \
        '[.tasks[] | select(.status == $e) | .id] | sort | .[]' 2>/dev/null)" \
        || block "JSON invalido en $path"

      nuevos=""
      while IFS= read -r vid; do
        [ -n "$vid" ] || continue
        printf '%s\n' "$antes_ids" | grep -qxF "$vid" || nuevos="$nuevos $vid"
      done <<IDS
$despues_ids
IDS

      [ -z "$nuevos" ] \
        || block "no puedes marcar $estado_exito a mano (${nuevos# }) — el estado lo mueve task.sh verify tras los gates, y task.sh merged tras el PR"
    done
  fi
elif [ "$protegido" = "config" ]; then
  # Se compara ANTES contra DESPUES en vez de buscar comandos triviales en una lista.
  # La lista negra la esquivaban "echo ok", "printf 100", "test 1 = 1" y hasta un
  # "true " con espacio final: enumerar formas de no hacer nada no tiene frontera.
  printf '%s' "$content" | jq -e . >/dev/null 2>&1 \
    || block "JSON invalido en $path — el harness no acepta un config corrupto"

  if [ -f "$path" ] && [ "${HARNESS_TASK_SH:-}" != "1" ]; then
    for clave in lint test coverage testRelated; do
      antes="$(jq -r --arg k "$clave" '.commands[$k] // ""' "$path" 2>/dev/null)"
      despues="$(printf '%s' "$content" | jq -r --arg k "$clave" '.commands[$k] // ""' 2>/dev/null)"
      [ "$antes" = "$despues" ] && continue
      block "no puedes cambiar commands.$clave en $path — un gate configurado no se toca sin pasar por task.sh"
    done

    umbral_antes="$(jq -r '.coverageThreshold // 0' "$path" 2>/dev/null)"
    umbral_despues="$(printf '%s' "$content" | jq -r '.coverageThreshold // 0' 2>/dev/null)"
    awk -v a="$umbral_antes" -v d="$umbral_despues" 'BEGIN { exit !(d + 0 >= a + 0) }' \
      || block "no puedes bajar coverageThreshold de $umbral_antes a $umbral_despues"

    # sonar.host y sonar.projectKey se tratan como commands.*: cualquier cambio bloquea.
    # Bloquear solo el BORRADO dejaba pasar host="http://127.0.0.1:1" y un projectKey
    # distinto, que tienen el mismo efecto exacto que borrarlo — verify.sh mapea un host
    # inalcanzable o un projectKey que no existe a skipped. El mensaje decia "eso
    # convierte un gate rojo en saltado" mientras la ruta que lo hace de verdad pasaba.
    for clave in host projectKey; do
      antes="$(jq -r --arg k "$clave" '.sonar[$k] // ""' "$path" 2>/dev/null)"
      despues="$(printf '%s' "$content" | jq -r --arg k "$clave" '.sonar[$k] // ""' 2>/dev/null)"
      [ "$antes" = "$despues" ] && continue
      block "no puedes cambiar sonar.$clave en $path — repuntar Sonar a otro host o a otro projectKey convierte un gate rojo en saltado igual que quitarlo"
    done
  fi
elif [ "$protegido" = "cases" ]; then
  nuevo="$(count_or_fail "$content" '.cases | arrays | length')" \
    || block "JSON invalido en $path — se esperaba un objeto con la lista de casos .cases; los contratos no se corrompen"
  [ -n "$nuevo" ] \
    || block "JSON invalido en $path — no se pudo contar la lista de casos .cases"
  if [ -f "$path" ]; then
    actual="$(jq -e '.cases | arrays | length' "$path" 2>/dev/null)" \
      || block "el archivo de aceptacion actual no tiene una lista .cases valida"
    [ "$nuevo" -ge "$actual" ] \
      || block "el cambio baja el numero de casos de aceptacion de $actual a $nuevo — los contratos no se borran"
  fi
elif [ "$protegido" = "tests" ]; then
  [ -n "$(printf '%s' "$content" | tr -d '[:space:]')" ] \
    || block "no puedes vaciar $path — los tests no se borran"
  if [ -f "$path" ]; then
    # grep -o y no grep -c: -c cuenta LINEAS coincidentes, no ocurrencias. Con dos
    # it( en la misma linea el conteo daba 1, y entonces borrar uno de los dos y
    # dejar el otro en su linea pasaba la guarda habiendo desaparecido un caso real.
    patron='it(\|test(\|describe(\|def test_\|@test'
    actual="$(grep -o "$patron" "$path" 2>/dev/null | wc -l | tr -d ' ')"
    nuevo="$(printf '%s' "$content" | grep -o "$patron" 2>/dev/null | wc -l | tr -d ' ')"
    [ "$nuevo" -ge "$actual" ] \
      || block "el cambio baja el numero de casos de test en $path de $actual a $nuevo"
  fi
else
  # Una clase protegida que este hook no sabe validar es exactamente el caso en el que
  # fallar cerrado es la unica respuesta correcta.
  block "$path esta protegido con la clase '$protegido' y este guard no sabe validarla"
fi

exit 0
