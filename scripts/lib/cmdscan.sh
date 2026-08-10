#!/usr/bin/env bash
# Escaneo de comandos y clasificacion de rutas protegidas, compartido por los hooks.
# Vive aqui y no duplicado en cada uno porque las dos listas de "ruta protegida" ya
# divergieron una vez: la rama de rm perdio *.bats mientras Edit/Write si lo protegia.

[ -n "${HARNESS_CMDSCAN_LOADED:-}" ] && return 0
HARNESS_CMDSCAN_LOADED=1

# Imprime un segmento por linea, partiendo por los separadores (& ; | y salto de
# linea) que estan FUERA de comillas y conservando el texto original de cada tramo.
#
# La version anterior VACIABA los tramos entrecomillados antes de partir. Evitaba el
# falso positivo de `echo "texto && git commit"`, pero al vaciarlos perdia el verbo:
# `"mv" /tmp/x .agent/tasks.json` quedaba en `"" /tmp/x .agent/tasks.json` y el
# comando pasaba entero. Partir respetando las comillas resuelve las dos cosas: no
# parte dentro de una cadena y no borra lo que hay escrito en ella.
#
# `>|` se normaliza a `>` ANTES de partir: si no, la barra de un redirect con clobber
# se leeria como separador de tuberia y el destino caeria en otro segmento.
cmd_segments() {
  local raw="${1//>|/>}" c q="" seg="" i=0 n nl
  nl='
'
  n=${#raw}
  while [ "$i" -lt "$n" ]; do
    c="${raw:$i:1}"
    i=$((i + 1))
    if [ -n "$q" ]; then
      seg="$seg$c"
      [ "$c" = "$q" ] && q=""
      continue
    fi
    case "$c" in
      '"'|"'")
        q="$c"
        seg="$seg$c"
        continue
        ;;
      '&'|';'|'|'|"$nl")
        seg="${seg#"${seg%%[![:space:]]*}"}"
        seg="${seg%"${seg##*[![:space:]]}"}"
        [ -n "$seg" ] && printf '%s\n' "$seg"
        seg=""
        continue
        ;;
    esac
    seg="$seg$c"
  done
  seg="${seg#"${seg%%[![:space:]]*}"}"
  seg="${seg%"${seg##*[![:space:]]}"}"
  [ -n "$seg" ] && printf '%s\n' "$seg"
  return 0
}

# Imprime el VERBO de un segmento: su PRIMERA palabra, sin comillas, sin la ruta que
# la precede y sin los envoltorios que no cambian lo que se ejecuta.
#
# Que se lea de la primera palabra y no de todo el segmento es justo lo que separa los
# dos casos que antes se contradecian: `"rm" -f tests/x` tiene que contar como rm,
# porque la shell lo ejecuta igual, y `echo "rm tests/x"` no, porque ahi rm es texto.
# Buscar el verbo en cualquier posicion daba el segundo; vaciar las comillas perdia el
# primero. La primera palabra da los dos.
cmd_verb() {
  local seg="$1" first rest
  while :; do
    seg="${seg#"${seg%%[![:space:]]*}"}"
    [ -n "$seg" ] || return 0
    first="${seg%%[[:space:]]*}"
    rest=""
    case "$seg" in
      *[[:space:]]*) rest="${seg#*[[:space:]]}" ;;
    esac
    first="$(printf '%s' "$first" | tr -d "\"'")"
    case "$first" in
      sudo|env|command|nohup|xargs|time|exec|builtin|then|else|elif|do|'{'|'!')
        [ -n "$rest" ] || break
        seg="$rest"
        continue
        ;;
      # Un prefijo NOMBRE=valor no cambia que programa corre. env FOO=1 tampoco (env
      # ya cae en el caso de arriba, pero la asignacion suelta no tenia manejo).
      [A-Za-z_]*=*)
        [ -n "$rest" ] || return 0
        seg="$rest"
        continue
        ;;
    esac
    break
  done
  printf '%s' "${first##*/}"
}

# Imprime cada palabra del comando con las comillas quitadas, no vaciadas. Sirve para
# buscar RUTAS en los argumentos, donde vaciar las comillas perderia justo el dato.
# Normaliza redirecciones (>|, >>, >) como tokens separados para detectar destinos.
cmd_words() {
  printf '%s' "$1" \
    | sed -e 's/>|/ > /g' -e 's/>>*/ > /g' \
    | tr -d "\"'" | tr '[:space:]' '\n' | sed -e '/^$/d'
}

# Clasifica una ruta, o retorna 1 si no la protegemos. Unica definicion, usada por la
# via Edit/Write y por la via Bash. Clases:
#
#   tasks       .agent/tasks.json — el registro de estado
#   config      .agent/config.json — los comandos que DEFINEN los gates
#   cases       .agent/acceptance/*.json — los contratos de aceptacion
#   reports     .agent/reports/*.json — la evidencia commiteada de verify.sh
#   guidelines  .agent/guidelines/ — la rubrica con la que se juzga el trabajo
#   agentdir    el directorio .agent en si, para que un rm -rf no lo vacie de golpe
#   harness     los hooks, la config de hooks y los scripts del propio harness
#   tests       los archivos de test
# Clase harness: el guard se protege a si mismo. Con estos archivos escribibles la
# promesa central de la plantilla — que el agente no puede declararse exitoso — se
# rompe en dos pasos: reescribir cmdscan.sh para que is_protected_path retorne 1 y
# despues escribir tasks.json con verified a mano. Los hooks releen el disco en cada
# invocacion, asi que no hace falta reiniciar la sesion.
#
# La lista enumera los ejecutables del harness en vez de usar scripts/*.sh a secas:
# scripts/ es tambien donde un proyecto adoptante pone su deploy.sh, y bloquear todo
# scripts/*.sh es la clase de sobre-bloqueo que termina con el hook desinstalado.
_is_harness_path() {
  local norm="$1"
  case "$norm" in
    .claude|.claude/|*/.claude|*/.claude/)                     return 0 ;;
    .claude/hooks|.claude/hooks/|*/.claude/hooks|*/.claude/hooks/) return 0 ;;
    .claude/hooks/*|*/.claude/hooks/*)                         return 0 ;;
    .claude/settings*.json|*/.claude/settings*.json)           return 0 ;;
    scripts/lib|scripts/lib/|*/scripts/lib|*/scripts/lib/)     return 0 ;;
    scripts/lib/*|*/scripts/lib/*)                             return 0 ;;
    scripts/task.sh|*/scripts/task.sh)                         return 0 ;;
    scripts/verify.sh|*/scripts/verify.sh)                     return 0 ;;
    scripts/bootstrap.sh|*/scripts/bootstrap.sh)               return 0 ;;
    scripts/doctor.sh|*/scripts/doctor.sh)                     return 0 ;;
    scripts/pipeline.sh|*/scripts/pipeline.sh)                 return 0 ;;
  esac
  return 1
}

# Un componente cuenta como test si TERMINA en test/tests/spec/specs, no si los
# contiene. "latest" contiene test y no lo es; "smoketest" termina en test y si.
# Aflojar esto a subcadena bloqueaba latest.txt; endurecerlo a lista fija dejaba
# unittests/ y testUtils.ts sin proteger.
_is_test_path() {
  # No hay regla morfologica: "smoketest" y "latest" terminan igual y lo que los
  # distingue es el significado. Se declara un contrato en vez de adivinar, igual que
  # con la cobertura. Un nombre que no encaje necesita separador o entrar en la lista.
  printf '%s' "$1" | awk '
    BEGIN { protegido = 0 }
    {
      n = split($0, parte, "/")
      for (i = 1; i <= n; i++) {
        comp = parte[i]
        if (comp ~ /\.bats$/) { protegido = 1; continue }
        base = comp
        sub(/\.[^.]*$/, "", base)
        nucleo = base
        gsub(/^_+|_+$/, "", nucleo)
        # componente completo, y la forma __tests__
        if (nucleo == "test" || nucleo == "tests" || nucleo == "spec" || nucleo == "specs") { protegido = 1; continue }
        # con separador a cualquiera de los dos lados
        if (base ~ /[-_.](test|tests|spec|specs)$/) { protegido = 1; continue }
        if (base ~ /^(test|tests|spec|specs)[-_.]/) { protegido = 1; continue }
        # compuestos pegados, lista declarada
        if (nucleo ~ /^(unit|integration|e2e|smoke|app|api|acceptance|regression|perf|load|snapshot|contract)(test|tests|spec|specs)$/) { protegido = 1; continue }
        # helpers de los que depende la suite
        if (base ~ /^test(utils|helpers|helper|util)$/) { protegido = 1; continue }
      }
    }
    END { exit !protegido }'
}

# Normaliza sin tocar el disco: colapsa barras repetidas, quita ./ y resuelve ..
# componente a componente. No se usa realpath porque la ruta puede no existir todavia
# —una escritura crea el archivo— y realpath fallaria justo en el caso que importa.
_norm_path() {
  printf '%s' "$1" | awk '
    {
      gsub(/\/+/, "/")
      n = split($0, parte, "/")
      salida = ""
      profundidad = 0
      for (i = 1; i <= n; i++) {
        if (parte[i] == "" || parte[i] == ".") continue
        if (parte[i] == "..") {
          if (profundidad > 0) { sub(/\/[^\/]*$/, "", salida); profundidad-- }
          else { salida = salida (salida == "" ? "" : "/") ".." }
          continue
        }
        salida = salida (salida == "" ? "" : "/") parte[i]
        profundidad++
      }
      print salida
    }' | tr '[:upper:]' '[:lower:]'
}

is_protected_path() {
  local norm
  norm="$(_norm_path "$1")"
  # El orden importa: las rutas de estado ganan sobre el patron generico de tests.
  case "$norm" in
    *.agent/tasks.json)              printf 'tasks' ;;
    *.agent/config.json)             printf 'config' ;;
    *.agent/acceptance/*.json)       printf 'cases' ;;
    *.agent/reports/*.json)          printf 'reports' ;;
    *.agent/guidelines|*.agent/guidelines/*) printf 'guidelines' ;;
    *.agent|*.agent/)                printf 'agentdir' ;;
    *) _is_harness_path "$norm" && printf 'harness' && return 0
       _is_test_path "$norm" && printf 'tests' && return 0
       return 1 ;;
  esac
}
