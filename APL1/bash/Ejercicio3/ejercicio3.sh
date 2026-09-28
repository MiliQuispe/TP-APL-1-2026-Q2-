#!/bin/bash

# Integrantes del grupo:
# Altamiranda Isaías
# Quispe, Milagros 45064110
# Puca, Micaela 39913189
# Penela, Santiago 44254763
# Sabes, Franco 38168884

# Función para mostrar la ayuda del script
mostrar_ayuda() {
    cat << EOF
Uso: $0 -d | --directorio <ruta_directorio>

Descripción:
  Identifica archivos duplicados (mismo nombre y tamaño) dentro de un directorio
  y sus subdirectorios de forma recursiva.

Parámetros:
  -d, --directorio  Ruta del directorio a analizar (obligatorio).
  -h, --help        Muestra este mensaje de ayuda.

Ejemplos de uso:
  $0 -d /home/usuario/documentos
  $0 --directorio "../mis_archivos"
EOF
}

DIRECTORIO=""

# Procesamiento de parámetros (admite cualquier orden)
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--directorio)
            if [[ -n "$2" && "$2" != -* ]]; then
                DIRECTORIO="$2"
                shift 2
            else
                echo "Error: El parámetro $1 requiere especificar una ruta de directorio válida." >&2
                exit 1
            fi
            ;;
        -h|--help)
            mostrar_ayuda
            exit 0
            ;;
        *)
            echo "Error: Parámetro no reconocido '$1'." >&2
            mostrar_ayuda
            exit 1
            ;;
    esac
done

# Validación de parámetro obligatorio
if [[ -z "$DIRECTORIO" ]]; then
    echo "Error: Debe ingresar el directorio a analizar con el parámetro -d o --directorio." >&2
    exit 1
fi

# Validación de existencia del directorio
if [[ ! -d "$DIRECTORIO" ]]; then
    echo "Error: La ruta '$DIRECTORIO' no existe o no es un directorio accesible." >&2
    exit 1
fi

# Obtener archivos recursivamente y procesar con AWK
find "$DIRECTORIO" -type f -exec ls -l {} + 2>/dev/null | awk '
BEGIN {
    num_keys = 0
}
/^-/ {
    size = $5
    
    # Reconstrucción del path completo (soporta nombres con espacios)
    path = $9
    for (i = 10; i <= NF; i++) {
        path = path " " $i
    }
    
    # Descomponer path en nombre de archivo y directorio
    n = split(path, a, "/")
    filename = a[n]
    
    dirname = ""
    for (i = 1; i < n; i++) {
        if (i > 1) dirname = dirname "/"
        dirname = dirname a[i]
    }
    if (dirname == "") dirname = "."
    
    # Clave única basada en Nombre + Tamaño
    key = filename "___" size
    
    if (!(key in count)) {
        order[++num_keys] = key
        names[key] = filename
        count[key] = 0
        paths[key] = ""
    }
    
    count[key]++
    if (paths[key] == "") {
        paths[key] = dirname
    } else {
        paths[key] = paths[key] "\n" dirname
    }
}
END {
    encontrados = 0
    for (k = 1; k <= num_keys; k++) {
        key = order[k]
        if (count[key] > 1) {
            encontrados = 1
            print names[key]
            print paths[key]
        }
    }
    if (encontrados == 0) {
        print "No se encontraron archivos duplicados."
    }
}'
