#!/usr/bin/env bash
#
# Integrantes del grupo:
# Altamiranda Isaías
# Quispe, Milagros 45064110
# Puca, Micaela 39913189
# Penela, Santiago 44254763
# Sabes, Franco 38168884
#
# ejercicio4.sh
#
# Proceso demonio que monitorea un directorio (y sus
# subdirectorios) y, cuando detecta que se creó un archivo
# duplicado de otro ya existente en el árbol (mismo nombre y
# mismo tamaño, igual criterio que el Ejercicio 3), genera un
# log y comprime los archivos involucrados en un .tar.gz dentro
# del directorio de salida, con nombre en formato
# yyyyMMdd-HHmmss.
#
# El mismo script permite además detener un demonio ya
# iniciado sobre un directorio, y evita que se inicien dos
# demonios sobre el mismo directorio al mismo tiempo.
#
# Uso:
#   ./ejercicio4.sh -d|--directorio <dir> -s|--salida <dir>
#   ./ejercicio4.sh -d|--directorio <dir> -k|--kill
#   ./ejercicio4.sh -h|--help
#
# Requisitos: inotify-tools (inotifywait), tar
# ============================================================

set -o pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly STATE_DIR="/tmp/.ejercicio4_daemons"
readonly INTERNAL_FLAG="--__internal-daemon-run"

# ------------------------------------------------------------
# print_error: muestra un mensaje de error amigable por stderr
# (pensado para un usuario sin conocimientos técnicos)
# ------------------------------------------------------------
print_error() {
    echo "" >&2
    echo "**********************************************************" >&2
    echo "ERROR: $1" >&2
    echo "**********************************************************" >&2
    echo "" >&2
}

# ------------------------------------------------------------
# show_help: muestra la ayuda de uso del script (-h / --help)
# ------------------------------------------------------------
show_help() {
    cat <<EOF
$SCRIPT_NAME - Demonio de detección de archivos duplicados

Uso:
  $SCRIPT_NAME -d <directorio> -s <directorio_salida>
      Inicia el demonio que monitorea <directorio> (incluyendo
      subdirectorios). Ante cada archivo nuevo que resulte
      duplicado (mismo nombre y tamaño que otro ya existente en
      el árbol), genera un log y un backup comprimido (.tar.gz)
      en <directorio_salida>.

  $SCRIPT_NAME -d <directorio> -k
      Detiene el demonio que esté corriendo sobre <directorio>.

  $SCRIPT_NAME -h | --help
      Muestra esta ayuda.

Parámetros:
  -d, --directorio  Ruta del directorio a monitorear (obligatorio).
  -s, --salida      Ruta del directorio donde se generan los backups
                     (obligatorio para iniciar el demonio).
  -k, --kill        Detiene el demonio iniciado sobre --directorio
                     (solo válido junto con -d/--directorio).
  -h, --help        Muestra esta ayuda.

Los parámetros pueden indicarse en cualquier orden. Las rutas
pueden ser relativas, absolutas o contener espacios.
EOF
}

# ------------------------------------------------------------
# check_dependencies: valida que existan los comandos externos
# que necesita el script antes de intentar usarlos
# ------------------------------------------------------------
check_dependencies() {
    local cmd
    for cmd in inotifywait tar find awk stat md5sum setsid; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            print_error "este script necesita el comando '$cmd', que no está instalado."
            exit 1
        fi
    done
}

# ------------------------------------------------------------
# get_absolute_path: convierte una ruta de directorio (relativa
# o absoluta, con o sin espacios) en su forma absoluta canónica.
# Devuelve una cadena vacía si el directorio no existe.
# ------------------------------------------------------------
get_absolute_path() {
    local path="$1"
    if [[ -d "$path" ]]; then
        (cd "$path" 2>/dev/null && pwd)
    else
        echo ""
    fi
}

# ------------------------------------------------------------
# get_state_file: dado un directorio absoluto, devuelve la ruta
# del archivo de estado (PID file) único para ese directorio
# ------------------------------------------------------------
get_state_file() {
    local abs_dir="$1"
    local hash
    hash=$(printf '%s' "$abs_dir" | md5sum | cut -d' ' -f1)
    echo "${STATE_DIR}/${hash}.pid"
}

# ------------------------------------------------------------
# is_daemon_running: retorna verdadero (0) si el archivo de
# estado indicado existe y el proceso que referencia está vivo
# ------------------------------------------------------------
is_daemon_running() {
    local state_file="$1"
    [[ -f "$state_file" ]] || return 1
    local pid
    pid=$(cat "$state_file" 2>/dev/null)
    [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

# ------------------------------------------------------------
# find_duplicate_paths: dado un archivo nuevo y el directorio
# raíz monitoreado, busca (con find + awk) otros archivos con
# el mismo nombre y el mismo tamaño en todo el árbol (mismo
# criterio de duplicado que el Ejercicio 3).
# Imprime, uno por línea, el path de cada duplicado encontrado.
# ------------------------------------------------------------
find_duplicate_paths() {
    local new_file="$1"
    local root_dir="$2"
    local new_name new_size

    new_name=$(basename -- "$new_file")
    new_size=$(stat -c%s -- "$new_file" 2>/dev/null) || return 1

    find "$root_dir" -type f -name "$new_name" ! -path "$new_file" -printf '%s|%p\n' 2>/dev/null \
        | awk -F'|' -v size="$new_size" '$1 == size { print $2 }'
}

# ------------------------------------------------------------
# create_backup: arma un directorio temporal en /tmp con copias
# de los archivos duplicados (preservando su ruta relativa al
# directorio monitoreado), los comprime como .tar.gz con nombre
# yyyyMMdd-HHmmss en el directorio de salida, escribe un log
# y garantiza la limpieza del temporal (trap).
# ------------------------------------------------------------
create_backup() {
    local new_file="$1"
    local root_dir="$2"
    local output_dir="$3"
    shift 3
    local duplicates=("$@")

    local timestamp tmp_dir
    timestamp=$(date +%Y%m%d-%H%M%S)
    tmp_dir=$(mktemp -d /tmp/ejercicio4_backup.XXXXXX)

    # Garantiza que el temporal se borre pase lo que pase en esta función
    trap 'rm -rf "$tmp_dir"' RETURN

    local log_file="${output_dir}/${timestamp}.log"
    local archive_file="${output_dir}/${timestamp}.tar.gz"

    {
        echo "Duplicado detectado: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Archivo nuevo: $new_file"
        echo "Coincidencias encontradas:"
        printf '  - %s\n' "${duplicates[@]}"
    } > "$log_file" 2>/dev/null

    local f rel_path dest_path
    for f in "$new_file" "${duplicates[@]}"; do
        rel_path="${f#"$root_dir"/}"
        dest_path="${tmp_dir}/${rel_path}"
        mkdir -p "$(dirname -- "$dest_path")" 2>/dev/null
        cp -- "$f" "$dest_path" 2>/dev/null
    done

    if ! tar -czf "$archive_file" -C "$tmp_dir" . 2>/dev/null; then
        print_error "no se pudo generar el backup comprimido en '$archive_file'."
    fi
}

# ------------------------------------------------------------
# monitor_loop: cuerpo del proceso demonio. Escucha eventos de
# creación de archivos con inotifywait y, ante cada uno, evalúa
# si es un duplicado y dispara la generación del backup.
# ------------------------------------------------------------
monitor_loop() {
    local watch_dir="$1"
    local output_dir="$2"
    local state_file="$3"

    # Limpieza garantizada al finalizar el demonio (fin normal,
    # señal de kill, o error) para no dejar archivos de estado
    trap 'rm -f "$state_file"; exit 0' TERM INT EXIT

    echo $$ > "$state_file"

    inotifywait -m -r -e create -e moved_to --format '%w%f' "$watch_dir" 2>/dev/null |
    while IFS= read -r new_file; do
        [[ -f "$new_file" ]] || continue

        mapfile -t duplicates < <(find_duplicate_paths "$new_file" "$watch_dir")

        if [[ ${#duplicates[@]} -gt 0 ]]; then
            create_backup "$new_file" "$watch_dir" "$output_dir" "${duplicates[@]}"
        fi
    done
}

# ------------------------------------------------------------
# start_daemon: valida que no exista ya un demonio para el
# mismo directorio, y lanza monitor_loop en segundo plano,
# desatado de la terminal, guardando su PID.
# ------------------------------------------------------------
start_daemon() {
    local dir="$1"
    local out="$2"

    local abs_dir
    abs_dir=$(get_absolute_path "$dir")
    if [[ -z "$abs_dir" ]]; then
        print_error "el directorio a monitorear '$dir' no existe."
        exit 1
    fi

    if [[ ! -d "$out" ]]; then
        mkdir -p "$out" 2>/dev/null || {
            print_error "no se pudo crear el directorio de salida '$out'."
            exit 1
        }
    fi
    local abs_out
    abs_out=$(get_absolute_path "$out")

    mkdir -p "$STATE_DIR"

    local state_file
    state_file=$(get_state_file "$abs_dir")

    if is_daemon_running "$state_file"; then
        print_error "ya existe un demonio en ejecución para el directorio '$abs_dir'."
        exit 1
    fi
    rm -f "$state_file" 2>/dev/null

    # setsid crea una nueva sesión/grupo de procesos: así, al
    # detener el demonio, podemos enviarle la señal a todo el
    # grupo (incluido inotifywait) y no solo al shell principal,
    # que de otro modo queda bloqueado esperando el pipeline y
    # nunca llega a procesar la señal.
    setsid nohup "$0" "$INTERNAL_FLAG" "$abs_dir" "$abs_out" "$state_file" >/dev/null 2>&1 &
    disown

    sleep 0.3
    if [[ -f "$state_file" ]]; then
        echo "Demonio iniciado correctamente sobre '$abs_dir' (PID $(cat "$state_file"))."
    else
        print_error "no se pudo iniciar el demonio."
        exit 1
    fi
}

# ------------------------------------------------------------
# stop_daemon: busca el demonio asociado al directorio indicado
# y, si está vivo, lo detiene (SIGTERM) y limpia su estado.
# ------------------------------------------------------------
stop_daemon() {
    local dir="$1"
    local abs_dir
    abs_dir=$(get_absolute_path "$dir")
    if [[ -z "$abs_dir" ]]; then
        print_error "el directorio '$dir' no existe."
        exit 1
    fi

    local state_file
    state_file=$(get_state_file "$abs_dir")

    if ! is_daemon_running "$state_file"; then
        print_error "no hay ningún demonio en ejecución para el directorio '$abs_dir'."
        rm -f "$state_file" 2>/dev/null
        exit 1
    fi

    local pid
    pid=$(cat "$state_file")

    # Se envía la señal a todo el grupo de procesos (nótese el
    # "-" antes del pid), no solo al shell principal, para que
    # también llegue a inotifywait y al subshell del pipeline.
    kill -TERM -- "-$pid" 2>/dev/null

    local waited=0
    while kill -0 "$pid" 2>/dev/null && [[ $waited -lt 50 ]]; do
        sleep 0.1
        waited=$((waited + 1))
    done

    if kill -0 "$pid" 2>/dev/null; then
        kill -KILL -- "-$pid" 2>/dev/null
        sleep 0.2
    fi

    if kill -0 "$pid" 2>/dev/null; then
        print_error "no se pudo detener el demonio (PID $pid). Intentelo nuevamente."
        exit 1
    fi

    rm -f "$state_file"
    echo "Demonio detenido correctamente para el directorio '$abs_dir'."
}

# ============================================================
# main: parseo de parámetros (en cualquier orden) y despacho
# ============================================================
main() {
    # Modo interno: esta es la re-ejecución que corre en
    # segundo plano y ES el demonio (no forma parte de la
    # interfaz pública del script).
    if [[ "$1" == "$INTERNAL_FLAG" ]]; then
        monitor_loop "$2" "$3" "$4"
        exit 0
    fi

    local directorio="" salida="" kill_flag=0

    local parsed
    parsed=$(getopt -o d:s:kh -l directorio:,salida:,kill,help -n "$SCRIPT_NAME" -- "$@") || {
        show_help
        exit 1
    }
    eval set -- "$parsed"

    while true; do
        case "$1" in
            -d|--directorio) directorio="$2"; shift 2 ;;
            -s|--salida) salida="$2"; shift 2 ;;
            -k|--kill) kill_flag=1; shift ;;
            -h|--help) show_help; exit 0 ;;
            --) shift; break ;;
            *) print_error "parámetro no reconocido."; exit 1 ;;
        esac
    done

    check_dependencies

    if [[ -z "$directorio" ]]; then
        print_error "el parámetro -d/--directorio es obligatorio."
        show_help
        exit 1
    fi

    if [[ "$kill_flag" -eq 1 ]]; then
        stop_daemon "$directorio"
    else
        if [[ -z "$salida" ]]; then
            print_error "el parámetro -s/--salida es obligatorio para iniciar el demonio."
            show_help
            exit 1
        fi
        start_daemon "$directorio" "$salida"
    fi
}

main "$@"
