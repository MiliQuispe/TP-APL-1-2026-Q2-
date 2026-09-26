<#
.SYNOPSIS
Consulta información sobre Star Wars a través de la API swapi.tech.

.DESCRIPTION
El script permite buscar información de personajes y películas por su ID. 
Implementa un sistema de caché local para evitar consultas de red redundantes.

.PARAMETER people
Array de números enteros que representan los IDs de los personajes a buscar.

.PARAMETER film
Array de números enteros que representan los IDs de las películas a buscar.

.EXAMPLE
.\swapi.ps1 -people 1,2 -film 1,3
#>

# Integrantes: Isaías Altamiranda

[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [int[]]$people,
    
    [Parameter(Mandatory=$false)]
    [int[]]$film
)

# 1. Validación de parámetro obligatorio
if (-not $people -and -not $film) {
    Write-Host "Error: Debes proveer al menos un ID de personaje (-people) o película (-film)."
    Get-Help $PSCommandPath
    exit
}

# 2. Configuración de Caché Persistente y Directorio Temporal
$cacheDir = ".\swapi_cache"
if (-not (Test-Path $cacheDir)) {
    New-Item -ItemType Directory -Path $cacheDir | Out-Null
}

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("swapi_" + [guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $tempDir | Out-Null

# 3. Bloque Try-Catch-Finally para manejo seguro de errores y limpieza
try {
    function Get-SwapiData {
        param([string]$type, [int[]]$ids)
        
        foreach ($id in $ids) {
            $cacheFile = Join-Path $cacheDir "${type}_${id}.json"
            
            # Lógica de Caché
            if (Test-Path $cacheFile) {
                # Se lee como objeto nativo desde el archivo
                $data = Get-Content $cacheFile -Raw | ConvertFrom-Json
            } else {
                $url = "https://www.swapi.tech/api/$type/$id"
                try {
                    $data = Invoke-RestMethod -Uri $url -Method Get
                    # Guardamos la respuesta cruda en la caché
                    $data | ConvertTo-Json -Depth 10 | Set-Content $cacheFile
                } catch {
                    Write-Host "Error: No se pudo encontrar el ID $id en la categoría $type o la red falló." -ForegroundColor Yellow
                    continue
                }
            }
            
            # Formateo visual e Impresión de propiedades del objeto
            if ($type -eq "people") {
                Write-Host "Personajes:"
                Write-Host "Id: $id"
                Write-Host "Name: $($data.result.properties.name)"
                Write-Host "Gender: $($data.result.properties.gender)"
                Write-Host "Height: $($data.result.properties.height)"
                Write-Host "Mass: $($data.result.properties.mass)"
                Write-Host "Birth Year: $($data.result.properties.birth_year)"
            } elseif ($type -eq "films") {
                Write-Host "Películas:"
                Write-Host "Title: $($data.result.properties.title)"
                Write-Host "Episode id: $($data.result.properties.episode_id)"
                Write-Host "Release date: $($data.result.properties.release_date)"
                Write-Host "Opening crawl: $($data.result.properties.opening_crawl)"
            }
            Write-Host ""
        }
    }

    if ($people) { Get-SwapiData -type "people" -ids $people }
    if ($film) { Get-SwapiData -type "films" -ids $film }

} catch {
    Write-Host "Ocurrió un error general inesperado procesando la consulta: $_" -ForegroundColor Red
} finally {
    # 4. Bloque Finally: Garantiza que se borren los temporales siempre
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force
    }
}