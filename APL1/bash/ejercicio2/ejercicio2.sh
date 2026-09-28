#!/bin/bash

# Integrantes del grupo:
# Quispe, Milagros 45064110
# Puca, Micaela 39913189

# función de ayuda (se la llama con -h / --help) -----
mostrar_ayuda() {
    cat << EOF
Uso: $0 -m <archivo_matriz> (-p <valor_entero> | -t) -s <separador>

Descripción:
  Realiza el producto escalar o la trasposición de una matriz leída desde un
  archivo de texto plano. Genera un archivo "salida.<nombreArchivoEntrada>"
  en el mismo directorio donde se encuentra el archivo de la matriz.

Parámetros obligatorios:
  -m, --matriz      Ruta del archivo de texto que contiene la matriz.
  -p, --producto    Valor entero para el producto escalar. No combinable con -t.
  -t, --trasponer   Realiza la trasposición de la matriz (sin valor adicional).
                    No combinable con -p.
  -s, --separador   Carácter separador de columnas (no puede ser un número ni "-").

Otros:
  -h, --help        Muestra este mensaje de ayuda.

Ejemplos:
  $0 -m ./matriz.txt -p 3 -s "|"
  $0 --matriz "/home/usuario/mi matriz.txt" --trasponer --separador ","
EOF
}

## lee el archivo de la matriz y valida su formato; imprime una fila por línea
## con sus valores separados por el carácter de control 0x1F (para uso interno)
leer_matriz() {
    local archivo="$1"
    local separador="$2"

    local contenido=()
    mapfile -t contenido < "$archivo"

    ### se elimina el retorno de carro (\r) por si el archivo viene con fin de línea de Windows
    local i
    for i in "${!contenido[@]}"; do
        contenido[i]="${contenido[i]%$'\r'}"
    done

    ### se descartan líneas en blanco al final del archivo
    while [ "${#contenido[@]}" -gt 0 ]; do
        local ultima="${contenido[${#contenido[@]}-1]}"
        if [ -n "$(echo "$ultima" | tr -d '[:space:]')" ]; then
            break
        fi
        unset 'contenido[${#contenido[@]}-1]'
        contenido=("${contenido[@]}")
    done

    if [ "${#contenido[@]}" -eq 0 ]; then
        echo "El archivo de la matriz está vacío." >&2
        return 1
    fi

    local columnas_esperadas=-1
    local num_fila=0
    local linea

    for linea in "${contenido[@]}"; do
        num_fila=$((num_fila + 1))

        if [ -z "$(echo "$linea" | tr -d '[:space:]')" ]; then
            echo "La matriz es inválida: la fila $num_fila está vacía." >&2
            return 1
        fi

        local campos=()
        IFS="$separador" read -r -a campos <<< "$linea"

        if [ "$columnas_esperadas" -eq -1 ]; then
            columnas_esperadas=${#campos[@]}
        elif [ "${#campos[@]}" -ne "$columnas_esperadas" ]; then
            echo "La matriz es inválida: la fila $num_fila tiene ${#campos[@]} columna(s) y se esperaban $columnas_esperadas." >&2
            return 1
        fi

        local fila_normalizada=""
        local valor limpio
        for valor in "${campos[@]}"; do
            read -r limpio <<< "$valor"
            if ! [[ "$limpio" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
                echo "La matriz es inválida: el valor '$valor' en la fila $num_fila no es un número válido." >&2
                return 1
            fi
            if [ -z "$fila_normalizada" ]; then
                fila_normalizada="$limpio"
            else
                fila_normalizada="${fila_normalizada}"$'\x1f'"${limpio}"
            fi
        done

        echo "$fila_normalizada"
    done
}

## traspone la matriz (filas por columnas)
trasponer_matriz() {
    local -a filas=("$@")
    local -a primera_fila
    IFS=$'\x1f' read -r -a primera_fila <<< "${filas[0]}"
    local columnas=${#primera_fila[@]}
    local filas_totales=${#filas[@]}

    local c f
    for (( c = 0; c < columnas; c++ )); do
        local nueva_fila=""
        for (( f = 0; f < filas_totales; f++ )); do
            local -a fila_actual
            IFS=$'\x1f' read -r -a fila_actual <<< "${filas[f]}"
            if [ -z "$nueva_fila" ]; then
                nueva_fila="${fila_actual[c]}"
            else
                nueva_fila="${nueva_fila}"$'\x1f'"${fila_actual[c]}"
            fi
        done
        echo "$nueva_fila"
    done
}

## multiplica cada elemento de la matriz por el factor escalar indicado
producto_escalar() {
    local factor="$1"
    shift
    local -a filas=("$@")
    local fila
    for fila in "${filas[@]}"; do
        local -a campos
        IFS=$'\x1f' read -r -a campos <<< "$fila"
        local nueva_fila=""
        local valor resultado
        for valor in "${campos[@]}"; do
            resultado=$(awk -v a="$valor" -v b="$factor" 'BEGIN { printf "%.10g", a * b }')
            if [ -z "$nueva_fila" ]; then
                nueva_fila="$resultado"
            else
                nueva_fila="${nueva_fila}"$'\x1f'"${resultado}"
            fi
        done
        echo "$nueva_fila"
    done
}

## convierte la matriz resultante (formato interno) a texto con el separador elegido
formatear_matriz() {
    local separador="$1"
    shift
    local -a filas=("$@")
    local fila
    for fila in "${filas[@]}"; do
        local -a campos
        IFS=$'\x1f' read -r -a campos <<< "$fila"
        local linea_salida=""
        local valor
        for valor in "${campos[@]}"; do
            if [ -z "$linea_salida" ]; then
                linea_salida="$valor"
            else
                linea_salida="${linea_salida}${separador}${valor}"
            fi
        done
        echo "$linea_salida"
    done
}

# inicialización de variables -----
ARCHIVO_MATRIZ=""
PRODUCTO=""
TRASPONER=0
SEPARADOR=""

# lectura y procesamiento de argumentos en cualquier orden -----
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            mostrar_ayuda
            exit 0
            ;;
        -m|--matriz)
            if [ $# -lt 2 ]; then
                echo "Error: El parámetro $1 requiere especificar la ruta del archivo de la matriz." >&2
                exit 1
            fi
            ARCHIVO_MATRIZ="$2"
            shift 2
            ;;
        -p|--producto)
            if [ $# -lt 2 ]; then
                echo "Error: El parámetro $1 requiere especificar un valor entero." >&2
                exit 1
            fi
            PRODUCTO="$2"
            shift 2
            ;;
        -t|--trasponer)
            TRASPONER=1
            shift 1
            ;;
        -s|--separador)
            if [ $# -lt 2 ]; then
                echo "Error: El parámetro $1 requiere especificar un carácter separador." >&2
                exit 1
            fi
            SEPARADOR="$2"
            shift 2
            ;;
        *)
            echo "Error: Parámetro desconocido '$1'. Use -h o --help para ver las opciones." >&2
            exit 1
            ;;
    esac
done

# validaciones de parámetros obligatorios -----
if [ -z "$ARCHIVO_MATRIZ" ]; then
    echo "Error: Falta indicar el archivo de la matriz (-m / --matriz)." >&2
    exit 1
fi

if [ -z "$SEPARADOR" ]; then
    echo "Error: Falta indicar el carácter separador (-s / --separador)." >&2
    exit 1
fi

if [ -z "$PRODUCTO" ] && [ "$TRASPONER" -eq 0 ]; then
    echo "Error: Debe indicar una operación: -p (producto escalar) o -t (trasponer)." >&2
    exit 1
fi

if [ -n "$PRODUCTO" ] && [ "$TRASPONER" -eq 1 ]; then
    echo "Error: No se pueden usar simultáneamente los parámetros -p y -t." >&2
    exit 1
fi

# validación del separador (un único carácter, no numérico ni "-") -----
if [ "${#SEPARADOR}" -ne 1 ]; then
    echo "Error: El separador debe ser un único carácter." >&2
    exit 1
fi

if [[ "$SEPARADOR" =~ [0-9] ]]; then
    echo "Error: El separador no puede ser un número." >&2
    exit 1
fi

if [ "$SEPARADOR" = "-" ]; then
    echo "Error: El separador no puede ser el símbolo '-' para no confundirlo con números negativos." >&2
    exit 1
fi

# validación del valor de producto -----
if [ -n "$PRODUCTO" ] && ! [[ "$PRODUCTO" =~ ^-?[0-9]+$ ]]; then
    echo "Error: El valor de -p / --producto debe ser un número entero." >&2
    exit 1
fi

# validación del archivo de la matriz (admite rutas relativas, absolutas y con espacios) -----
if [ ! -f "$ARCHIVO_MATRIZ" ]; then
    echo "Error: El archivo de la matriz especificado '$ARCHIVO_MATRIZ' no existe o no es accesible." >&2
    exit 1
fi

DIRECTORIO_ENTRADA=$(cd "$(dirname "$ARCHIVO_MATRIZ")" 2>/dev/null && pwd)
if [ -z "$DIRECTORIO_ENTRADA" ]; then
    echo "Error: No fue posible acceder al directorio del archivo de la matriz." >&2
    exit 1
fi

NOMBRE_ARCHIVO=$(basename "$ARCHIVO_MATRIZ")
RUTA_MATRIZ_ABS="$DIRECTORIO_ENTRADA/$NOMBRE_ARCHIVO"
ARCHIVO_SALIDA="$DIRECTORIO_ENTRADA/salida.$NOMBRE_ARCHIVO"

# lectura y validación de la matriz de entrada (los mensajes de error se muestran desde la función) -----
SALIDA_LECTURA=$(leer_matriz "$RUTA_MATRIZ_ABS" "$SEPARADOR")
if [ $? -ne 0 ]; then
    exit 1
fi
mapfile -t MATRIZ <<< "$SALIDA_LECTURA"

# cálculo según la operación solicitada -----
if [ "$TRASPONER" -eq 1 ]; then
    SALIDA_CALCULO=$(trasponer_matriz "${MATRIZ[@]}")
else
    SALIDA_CALCULO=$(producto_escalar "$PRODUCTO" "${MATRIZ[@]}")
fi

if [ $? -ne 0 ]; then
    echo "Error: Ocurrió un inconveniente al procesar la matriz." >&2
    exit 1
fi
mapfile -t MATRIZ_RESULTADO <<< "$SALIDA_CALCULO"

# generación del archivo de salida -----
if ! formatear_matriz "$SEPARADOR" "${MATRIZ_RESULTADO[@]}" > "$ARCHIVO_SALIDA"; then
    echo "Error: No fue posible generar el archivo de salida en '$ARCHIVO_SALIDA'." >&2
    exit 1
fi

echo "Archivo de salida generado exitosamente en: $ARCHIVO_SALIDA"
exit 0
