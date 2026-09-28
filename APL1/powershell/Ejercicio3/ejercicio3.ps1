# Integrantes del grupo:
# Altamiranda Isaías
# Quispe, Milagros 45064110
# Puca, Micaela 39913189
# Penela, Santiago 44254763
# Sabes, Franco 38168884

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Ingrese la ruta del directorio a analizar.")]
    [ValidateNotNullOrEmpty()]
    [string]$directorio
)

<#
.SYNOPSIS
    Identifica archivos duplicados (mismo nombre y tamaño) en un directorio y sus subdirectorios.
.DESCRIPTION
    Busca archivos repetidos basándose exclusivamente en la coincidencia de nombre y tamaño.
    Muestra en pantalla el nombre del archivo duplicado seguido de las rutas de los directorios donde se encuentra.
.PARAMETER directorio
    Ruta del directorio a analizar (relativa o absoluta).
.EXAMPLE
    Get-Help ./ejercicio3.ps1
.EXAMPLE
    ./ejercicio3.ps1 -directorio "/home/santiago/apl"
#>

try {
    if (-not (Test-Path -Path $directorio -PathType Container)) {
        Write-Error "El directorio especificado no existe o no es accesible: '$directorio'" -ErrorAction Stop
    }

    $rutaAbsoluta = (Get-Item -Path $directorio).FullName

    $archivos = Get-ChildItem -Path $rutaAbsoluta -Recurse -File -ErrorAction Stop

    $duplicados = $archivos | Group-Object -Property Name, Length | Where-Object { $_.Count -gt 1 }

    if (-not $duplicados) {
        Write-Output "No se encontraron archivos duplicados en '$directorio'."
        exit 0
    }

    foreach ($grupo in $duplicados) {
        # Imprime el nombre del archivo
        Write-Output $grupo.Group[0].Name
        
        foreach ($archivo in $grupo.Group) {
            Write-Output $archivo.DirectoryName
        }
    }
}
catch {
    Write-Error "Ocurrió un error inesperado al procesar los archivos: $_"
}
