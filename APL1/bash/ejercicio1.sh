
#!/usr/bin/env bash

###############################################################################
# Cátedra de Sistemas Operativos - UNLaM
# APL 1 - Ejercicio 1: Validación de Lotería
# 
# Integrantes:
# - Quispe, Milagros 45064110
###############################################################################

# definición y limpieza de temporales con trap -----
TEMP_DIR="/tmp/apl1_ej1_$$" #garantiza que el nombre de la carpeta en /tmp sea único
mkdir -p "$TEMP_DIR"

limpiar() {
    rm -rf "$TEMP_DIR" 2>/dev/null
}
trap limpiar EXIT INT TERM

# función de ayuda (el se lo llama cuando se realiza -h / --help)-----
mostrar_ayuda() {
    cat << EOF
Uso: $0 -d <directorio> (-a <archivo_salida> | -p) [-g <archivo_ganadores>]

Parámetros requeridos:
  -d, --directorio    Ruta del directorio que contiene los archivos CSV de agencias.
  
Opciones de salida (mutuamente excluyentes):
  -a, --archivo       Ruta completa del archivo JSON donde se guardará el resultado.
  -p, --pantalla      Muestra la salida formateada en JSON por consola.

Parámetros opcionales:
  -g, --ganadores     Ruta al archivo CSV con los 5 números ganadores.
                      (Por defecto busca 'ganadores.csv' dentro de -d).
  -h, --help          Muestra este mensaje de ayuda.
EOF
    exit 0
}

# inicialización de variables-----
DIR_ENTRADA=""
ARCHIVO_SALIDA=""
SALIDA_PANTALLA=0
ARCHIVO_GANADORES=""

# lectura y procesamiento de argumentos en cualquier orden (usando while, case y shift)-----
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            mostrar_ayuda
            ;;
        -d|--directorio)
            DIR_ENTRADA="$2"
            shift 2 #se desplaza de argumento con shift
            ;;
        -a|--archivo)
            ARCHIVO_SALIDA="$2"
            shift 2
            ;;
        -p|--pantalla)
            SALIDA_PANTALLA=1
            shift 1
            ;;
        -g|--ganadores)
            ARCHIVO_GANADORES="$2"
            shift 2
            ;;
        *)
            echo "Error: Parámetro desconocido '$1'. Use -h o --help para ver las opciones." >&2 
            exit 1
            ;;
    esac
done

#   validaciones de negocio y parámetros obligatorios-----
if [ -z "$DIR_ENTRADA" ]; then
    echo "Error: Falta indicar el directorio de agencias (-d / --directorio)." >&2
    exit 1
fi

if [ ! -d "$DIR_ENTRADA" ]; then
    echo "Error: El directorio '$DIR_ENTRADA' no existe o no es accesible." >&2
    exit 1
fi

if [ -n "$ARCHIVO_SALIDA" ] && [ "$SALIDA_PANTALLA" -eq 1 ]; then
    echo "Error: No se pueden usar simultáneamente los parámetros de salida -a y -p." >&2
    exit 1
fi

if [ -z "$ARCHIVO_SALIDA" ] && [ "$SALIDA_PANTALLA" -eq 0 ]; then
    echo "Error: Debe indicar un destino de salida: -p (pantalla) o -a (archivo)." >&2
    exit 1
fi

##       archivo de ganadores
if [ -z "$ARCHIVO_GANADORES" ]; then
    ARCHIVO_GANADORES="$DIR_ENTRADA/ganadores.csv"
fi

if [ ! -f "$ARCHIVO_GANADORES" ]; then
    echo "Error: No se encontró el archivo de números ganadores en '$ARCHIVO_GANADORES'." >&2 #las advertencias se dirigen al canal de error estándar
    exit 1
fi

#   lectura y normalización de números ganadores (eliminando \r)----
LINEA_GANADORES=$(tr -d '\r' < "$ARCHIVO_GANADORES" | head -n 1)
IFS=',' read -r -a GANADORES <<< "$LINEA_GANADORES"

##       Archivos temporales para acumular elementos por acierto
TMP_5="$TEMP_DIR/5.tmp"
TMP_4="$TEMP_DIR/4.tmp"
TMP_3="$TEMP_DIR/3.tmp"
touch "$TMP_5" "$TMP_4" "$TMP_3"

#   procesamiento de archivos de agencia-------
for archivo_csv in "$DIR_ENTRADA"/*.csv; do
    [ ! -f "$archivo_csv" ] && continue

    ## omitir el archivo de ganadores si está en la misma carpeta
    NOMBRE_BASE=$(basename "$archivo_csv")
    if [ "$archivo_csv" -ef "$ARCHIVO_GANADORES" ] || [ "$NOMBRE_BASE" = "ganadores.csv" ]; then
        continue
    fi

    ## el nombre del archivo representa el identificador de la agencia
    AGENCIA="${NOMBRE_BASE%.csv}"

    ##Lectura línea a línea limpiando fin de línea DOS/Windows (\r)
    while IFS= read -r linea || [ -n "$linea" ]; do
        linea=$(echo "$linea" | tr -d '\r' | xargs)
        [ -z "$linea" ] && continue

        IFS=',' read -r -a JUGADA <<< "$linea"
        ID_JUGADA="${JUGADA[0]}"

        ### contar aciertos comparando los 5 números
        ACIERTOS=0
        for (( i=1; i<${#JUGADA[@]}; i++ )); do
            NUM="${JUGADA[i]}"
            for GAN in "${GANADORES[@]}"; do
                if [ "$NUM" -eq "$GAN" ]; then
                    ACIERTOS=$((ACIERTOS + 1))
                    break
                fi
            done
        done

        ## formato de entrada JSON
        BLOQUE="      {\n         \"agencia\": \"$AGENCIA\",\n         \"jugada\": \"$ID_JUGADA\"\n      }"

        case "$ACIERTOS" in
            5) echo -e "$BLOQUE" >> "$TMP_5" ;; #guardar el bloque en el archivo temporal 
            4) echo -e "$BLOQUE" >> "$TMP_4" ;;
            3) echo -e "$BLOQUE" >> "$TMP_3" ;;
        esac
    done < "$archivo_csv"
done

## función para convertir las entradas recolectadas en una lista JSON válida
armar_seccion_json() {
    local archivo="$1"
    if [ ! -s "$archivo" ]; then
        echo " []"
    else
        echo " ["
        ### agrega comas entre llaves de cierre de cada objeto excepto en el último
        sed '$!s/}$/},/' "$archivo"
        echo "   ]"
    fi
}

# construcción del JSON final--------
JSON_FINAL="{\n   \"5_aciertos\":$(armar_seccion_json "$TMP_5"),\n   \"4_aciertos\":$(armar_seccion_json "$TMP_4"),\n   \"3_aciertos\":$(armar_seccion_json "$TMP_3")\n}"

# salida por la pantalla-----
if [ "$SALIDA_PANTALLA" -eq 1 ]; then
    echo -e "$JSON_FINAL"
else
    ## crea la carpeta de destino si no existe
    mkdir -p "$(dirname "$ARCHIVO_SALIDA")"
    echo -e "$JSON_FINAL" > "$ARCHIVO_SALIDA"
    echo "Reporte generado correctamente en '$ARCHIVO_SALIDA'."
fi