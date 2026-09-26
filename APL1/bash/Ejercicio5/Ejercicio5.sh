#!/bin/bash
# Integrantes: Altamiranda Isaías

# ayuda del script
show_help() {
    echo "Uso: $0 [-p|--people id1,id2] [-f|--film id1,id2]"
    echo "  -p, --people   Id o ids de los personajes a buscar (separados por coma)."
    echo "  -f, --film     Id o ids de las películas a buscar (separados por coma)."
    echo "  -h, --help     Muestra esta ayuda."
}

# arch temporales y el trap para elimiarlo si pasa alfo
TEMP_DIR=$(mktemp -d /tmp/swapi_XXXXXX)
trap 'rm -rf "$TEMP_DIR"' EXIT ERR INT TERM

# cache local
CACHE_DIR="./swapi_cache"
mkdir -p "$CACHE_DIR"

# parsear de parametros con el getopt
TEMP=$(getopt -o p:f:h --long people:,film:,help -n "$0" -- "$@")
if [ $? -ne 0 ]; then
    echo "Error: Ocurrió un problema al leer los parámetros proporcionados." >&2
    exit 1
fi
eval set -- "$TEMP"

PEOPLE=""
FILMS=""

# asignar var segun parametro
while true; do
    case "$1" in
        -p|--people) PEOPLE="$2"; shift 2 ;;
        -f|--film) FILMS="$2"; shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        --) shift; break ;;
        *) echo "Error: Parámetro inválido."; exit 1 ;;
    esac
done

# validar parametros
if [ -z "$PEOPLE" ] && [ -z "$FILMS" ]; then
    echo "Error: Debes ingresar al menos un parámetro (-p o -f) para realizar la búsqueda."
    show_help
    exit 1
fi

# imprimir
fetch_data() {
    local type="$1"
    local ids="$2"
    
    ids_list=$(echo "$ids" | tr ',' ' ')
    
    for id in $ids_list; do
        cache_file="$CACHE_DIR/${type}_${id}.json"
        temp_file="$TEMP_DIR/resp.json"
        
        if [ -f "$cache_file" ]; then
            cp "$cache_file" "$temp_file"
        else
            http_code=$(curl -s -w "%{http_code}" -o "$temp_file" "https://www.swapi.tech/api/${type}/${id}")
            
            if [ "$http_code" -ne 200 ]; then
                echo "Error: No se encontró información para el ID $id en la categoría $type."
                continue
            fi
            cp "$temp_file" "$cache_file"
        fi
        

        if [ "$type" == "people" ]; then
            name=$(grep -o '"name":"[^"]*"' "$temp_file" | head -n 1 | cut -d':' -f2 | tr -d '"')
            gender=$(grep -o '"gender":"[^"]*"' "$temp_file" | head -n 1 | cut -d':' -f2 | tr -d '"')
            height=$(grep -o '"height":"[^"]*"' "$temp_file" | head -n 1 | cut -d':' -f2 | tr -d '"')
            mass=$(grep -o '"mass":"[^"]*"' "$temp_file" | head -n 1 | cut -d':' -f2 | tr -d '"')
            birth_year=$(grep -o '"birth_year":"[^"]*"' "$temp_file" | head -n 1 | cut -d':' -f2 | tr -d '"')
            
            echo "Personajes:"
            echo "Id: $id"
            echo "Name: $name"
            echo "Gender: $gender"
            echo "Height: $height"
            echo "Mass: $mass"
            echo "Birth Year: $birth_year"
            
        elif [ "$type" == "films" ]; then
            title=$(grep -o '"title":"[^"]*"' "$temp_file" | head -n 1 | cut -d':' -f2 | tr -d '"')
            episode_id=$(grep -o '"episode_id":[0-9]*' "$temp_file" | head -n 1 | cut -d':' -f2)
            release_date=$(grep -o '"release_date":"[^"]*"' "$temp_file" | head -n 1 | cut -d':' -f2 | tr -d '"')
            
            opening_crawl=$(grep -o '"opening_crawl":"[^"]*"' "$temp_file" | head -n 1 | cut -d':' -f2- | tr -d '"')
            
            echo "Películas:"
            echo -e "\nTitle: $title"
            echo -e "\nEpisode id: $episode_id"
            echo -e "\nRelease date: $release_date"
            echo -e "\nOpening crawl: \n$opening_crawl"
        fi
        echo ""
    done
}

[ -n "$PEOPLE" ] && fetch_data "people" "$PEOPLE"
[ -n "$FILMS" ] && fetch_data "films" "$FILMS"