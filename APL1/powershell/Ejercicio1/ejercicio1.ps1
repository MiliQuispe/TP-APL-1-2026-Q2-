# Integrantes del grupo:
# Altamiranda Isaías
# Quispe, Milagros 45064110
# Puca, Micaela 39913189
# Penela, Santiago 44254763
# Sabes, Franco 38168884

#ayuda
<#
.SYNOPSIS
    Procesa las jugadas semanales de agencias de lotería y clasifica por aciertos.
.DESCRIPTION
    Script del Ejercicio 1 
.PARAMETER directorio
    Ruta del directorio que contiene los archivos CSV de agencias.
.PARAMETER archivo
    Ruta completa del archivo JSON a generar (no combinable con -pantalla).
.PARAMETER pantalla
    Muestra la salida en formato JSON por pantalla (no combinable con -archivo).
.PARAMETER ganadores
    Ruta alternativa al archivo CSV con los 5 números ganadores.
.EXAMPLE
    Get-Help ./ejercicio1.ps1
.EXAMPLE
    ./ejercicio1.ps1 -directorio ./pruebas -pantalla
.EXAMPLE
    ./ejercicio1.ps1 -directorio ./pruebas -archivo ./salida.json
#>

#Validación nativa en param(...)
[CmdletBinding(DefaultParameterSetName = 'PorPantalla')]

param (
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Directorio con los archivos CSV.")]
    [ValidateNotNullOrEmpty()]
    [string]$directorio,

    [Parameter(Mandatory = $true, ParameterSetName = 'PorArchivo', HelpMessage = "Ruta completa del archivo de salida JSON.")]
    [ValidateNotNullOrEmpty()]
    [string]$archivo,

    [Parameter(Mandatory = $true, ParameterSetName = 'PorPantalla', HelpMessage = "Mostrar salida por pantalla.")]
    [switch]$pantalla,

    [Parameter(Mandatory = $false, HelpMessage = "Ruta al archivo CSV de ganadores.")]
    [string]$ganadores
)


#por falla inesperada en tiempo de ejecucion
try {
    ## Validación del directorio de agencias
    if (-not (Test-Path -Path $directorio -PathType Container)) {
        Write-Error "El directorio especificado '$directorio' no existe o no es accesible."
        exit 1
    }

    $rutaDirectorio = (Resolve-Path -Path $directorio).Path

    ##Localizar archivo de ganadores
    if ([string]::IsNullOrWhiteSpace($ganadores)) {
        $rutaGanadores = Join-Path -Path $rutaDirectorio -ChildPath "ganadores.csv"
    } else {
        if (-not (Test-Path -Path $ganadores -PathType Leaf)) {
            Write-Error "No se encontró el archivo de ganadores indicado en: $ganadores"
            exit 1
        }
        $rutaGanadores = (Resolve-Path -Path $ganadores).Path
    }

    if (-not (Test-Path -Path $rutaGanadores -PathType Leaf)) {
        Write-Error "No se encontró el archivo 'ganadores.csv' dentro de $rutaDirectorio"
        exit 1
    }

    ### Leer los 5 números ganadores
    $lineaGanadores = Get-Content -Path $rutaGanadores -TotalCount 1
    $numerosGanadores = $lineaGanadores.Trim().Split(',') | ForEach-Object { [int]$_.Trim() }

    ### Estructura ordenada para mantener la jerarquía 
    $salida = [ordered]@{
        "5_aciertos" = [System.Collections.Generic.List[PSObject]]::new()
        "4_aciertos" = [System.Collections.Generic.List[PSObject]]::new()
        "3_aciertos" = [System.Collections.Generic.List[PSObject]]::new()
    }

    ##Procesar archivos CSV de agencias
    $archivos = Get-ChildItem -Path $rutaDirectorio -Filter *.csv | Where-Object { $_.FullName -ne $rutaGanadores }

    foreach ($archivoAgencia in $archivos) {
        $nombreAgencia = [System.IO.Path]::GetFileNameWithoutExtension($archivoAgencia.Name)
        $lineas = Get-Content -Path $archivoAgencia.FullName

        foreach ($linea in $lineas) {
            if ([string]::IsNullOrWhiteSpace($linea)) { continue }

            $partes = $linea.Trim().Split(',')
            $idJugada = $partes[0].Trim()
            $numerosJugada = $partes[1..($partes.Length - 1)] | ForEach-Object { [int]$_.Trim() }

            ### Contar coincidencias
            $aciertos = ($numerosJugada | Where-Object { $numerosGanadores -contains $_ }).Count

            #### Estructura de cada registro
            $registro = [PSCustomObject]@{
                agencia = [string]$nombreAgencia
                jugada  = [string]$idJugada
            }

            switch ($aciertos) {
                5 { $salida["5_aciertos"].Add($registro) }
                4 { $salida["4_aciertos"].Add($registro) }
                3 { $salida["3_aciertos"].Add($registro) }
            }
        }
    }

    ## Generación del JSON nativo
    $jsonResultado = $salida | ConvertTo-Json -Depth 4

    ## Salida por pantalla o archivo
    if ($pantalla.IsPresent) {
        Write-Output $jsonResultado
    } else {
        $directorioDestino = [System.IO.Path]::GetDirectoryName($archivo)
        if (-not [string]::IsNullOrEmpty($directorioDestino) -and -not (Test-Path $directorioDestino)) {
            New-Item -ItemType Directory -Path $directorioDestino -Force | Out-Null
        }
        $jsonResultado | Out-File -FilePath $archivo -Encoding utf8
        Write-Host "Archivo JSON generado exitosamente en: $archivo"
    }

} catch {
    Write-Error "Ocurrió un inconveniente al procesar las jugadas: $($_.Exception.Message)"
    exit 1
}
