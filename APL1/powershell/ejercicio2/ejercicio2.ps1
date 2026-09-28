# Integrantes del grupo:
# Quispe, Milagros 45064110
# Puca, Micaela 39913189

<#
.SYNOPSIS
    Realiza el producto escalar o la trasposición de una matriz leída desde un archivo de texto.
.DESCRIPTION
    Script del Ejercicio 2. Lee una matriz desde un archivo de texto plano (valores numéricos
    separados por un caracter indicado), valida que la matriz sea válida (mismas columnas por
    fila y valores numéricos) y genera un archivo de salida llamado "salida.<nombreArchivoEntrada>"
    en el mismo directorio donde se encuentra el archivo de entrada.
.PARAMETER matriz
    Ruta (relativa o absoluta) del archivo de texto que contiene la matriz.
.PARAMETER producto
    Valor entero para realizar el producto escalar sobre la matriz. No combinable con -trasponer.
.PARAMETER trasponer
    Indica que se debe realizar la trasposición de la matriz. No combinable con -producto.
.PARAMETER separador
    Caracter utilizado como separador de columnas dentro del archivo de la matriz.
    No puede ser un número ni el símbolo "-".
.EXAMPLE
    Get-Help ./ejercicio2.ps1
.EXAMPLE
    ./ejercicio2.ps1 -matriz ./matriz.txt -producto 3 -separador "|"
.EXAMPLE
    ./ejercicio2.ps1 -matriz "C:\datos\mi matriz.txt" -trasponer -separador ","
#>

[CmdletBinding(DefaultParameterSetName = 'Producto')]
param (
    [Parameter(HelpMessage = "Ruta del archivo de la matriz.")]
    [ValidateNotNullOrEmpty()]
    [string]$matriz,

    [Parameter(ParameterSetName = 'Producto', HelpMessage = "Valor entero para el producto escalar.")]
    [int]$producto,

    [Parameter(ParameterSetName = 'Trasponer', HelpMessage = "Realizar la trasposición de la matriz.")]
    [switch]$trasponer,

    [Parameter(HelpMessage = "Caracter separador de columnas.")]
    [ValidateScript({
        if ($_.Length -ne 1) {
            throw "El separador debe ser un único caracter."
        }
        if ($_ -match '[0-9]') {
            throw "El separador no puede ser un numero."
        }
        if ($_ -eq '-') {
            throw "El separador no puede ser el simbolo '-' para no confundirlo con numeros negativos."
        }
        return $true
    })]
    [string]$separador
)

## Convierte el contenido del archivo de la matriz en una matriz numérica, validando su formato
function ConvertTo-Matriz {
    param(
        [string]$Ruta,
        [string]$Separador
    )

    $contenido = @(Get-Content -Path $Ruta -ErrorAction Stop)

    ### se descartan líneas en blanco al final del archivo (por ejemplo, salto de línea final)
    while ($contenido.Count -gt 0 -and [string]::IsNullOrWhiteSpace($contenido[-1])) {
        $contenido = $contenido[0..($contenido.Count - 2)]
    }

    if ($contenido.Count -eq 0) {
        throw "El archivo de la matriz está vacío."
    }

    $separadorEscapado = [regex]::Escape($Separador)
    $columnasEsperadas = -1
    $filasMatriz = @()

    for ($i = 0; $i -lt $contenido.Count; $i++) {
        $numeroFila = $i + 1
        $linea = $contenido[$i]

        if ([string]::IsNullOrWhiteSpace($linea)) {
            throw "La matriz es inválida: la fila $numeroFila está vacía."
        }

        $tokens = [regex]::Split($linea.Trim(), $separadorEscapado)

        if ($columnasEsperadas -eq -1) {
            $columnasEsperadas = $tokens.Count
        } elseif ($tokens.Count -ne $columnasEsperadas) {
            throw "La matriz es inválida: la fila $numeroFila tiene $($tokens.Count) columna(s) y se esperaban $columnasEsperadas."
        }

        $filaNumerica = @()
        foreach ($token in $tokens) {
            $valor = 0.0
            $textoLimpio = $token.Trim()
            if (-not [double]::TryParse($textoLimpio, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$valor)) {
                throw "La matriz es inválida: el valor '$token' en la fila $numeroFila no es un número válido."
            }
            $filaNumerica += , $valor
        }
        $filasMatriz += , $filaNumerica
    }

    return , $filasMatriz
}

## Genera la matriz traspuesta (filas por columnas)
function Get-MatrizTraspuesta {
    param($Matriz)

    $cantidadFilas = $Matriz.Count
    $cantidadColumnas = $Matriz[0].Count
    $resultado = @()

    for ($columna = 0; $columna -lt $cantidadColumnas; $columna++) {
        $nuevaFila = @()
        for ($fila = 0; $fila -lt $cantidadFilas; $fila++) {
            $nuevaFila += , $Matriz[$fila][$columna]
        }
        $resultado += , $nuevaFila
    }

    return , $resultado
}

## Multiplica cada elemento de la matriz por el factor escalar indicado
function Get-ProductoEscalar {
    param(
        $Matriz,
        [int]$Factor
    )

    $resultado = @()
    foreach ($fila in $Matriz) {
        $nuevaFila = @()
        foreach ($valor in $fila) {
            $nuevaFila += , ($valor * $Factor)
        }
        $resultado += , $nuevaFila
    }

    return , $resultado
}

## Convierte la matriz resultante en texto, usando el separador indicado
function ConvertTo-TextoMatriz {
    param(
        $Matriz,
        [string]$Separador
    )

    return $Matriz | ForEach-Object {
        ($_ | ForEach-Object { $_.ToString([System.Globalization.CultureInfo]::InvariantCulture) }) -join $Separador
    }
}

## Validación manual de parámetros obligatorios (sin solicitar ingreso interactivo)
$parametrosFaltantes = @()

if (-not $PSBoundParameters.ContainsKey('matriz') -or [string]::IsNullOrWhiteSpace($matriz)) {
    $parametrosFaltantes += "matriz"
}
if (-not $PSBoundParameters.ContainsKey('separador') -or [string]::IsNullOrWhiteSpace($separador)) {
    $parametrosFaltantes += "separador"
}
if (-not $PSBoundParameters.ContainsKey('producto') -and -not $PSBoundParameters.ContainsKey('trasponer')) {
    $parametrosFaltantes += "producto o trasponer"
}

if ($parametrosFaltantes.Count -gt 0) {
    Write-Host "Error: Falta indicar el parametro obligatorio '$($parametrosFaltantes -join "', '")'." -ForegroundColor Red
    exit 1
}

#por falla inesperada en tiempo de ejecución
try {
    ## Validación del archivo de la matriz
    if (-not (Test-Path -Path $matriz -PathType Leaf)) {
        Write-Error "El archivo de la matriz especificado '$matriz' no existe o no es accesible."
        exit 1
    }

    $rutaMatrizAbsoluta = (Resolve-Path -Path $matriz).Path
    $directorioEntrada = Split-Path -Path $rutaMatrizAbsoluta -Parent
    $nombreArchivoEntrada = Split-Path -Path $rutaMatrizAbsoluta -Leaf
    $rutaSalida = Join-Path -Path $directorioEntrada -ChildPath "salida.$nombreArchivoEntrada"

    ## Lectura y validación de la matriz de entrada
    $matrizEntrada = ConvertTo-Matriz -Ruta $rutaMatrizAbsoluta -Separador $separador

    ## Cálculo según la operación solicitada
    if ($PSCmdlet.ParameterSetName -eq 'Trasponer') {
        $matrizResultado = Get-MatrizTraspuesta -Matriz $matrizEntrada
    } else {
        $matrizResultado = Get-ProductoEscalar -Matriz $matrizEntrada -Factor $producto
    }

    ## Generación del archivo de salida
    $textoSalida = ConvertTo-TextoMatriz -Matriz $matrizResultado -Separador $separador
    $textoSalida | Out-File -FilePath $rutaSalida -Encoding utf8

    Write-Host "Archivo de salida generado exitosamente en: $rutaSalida"

} catch {
    Write-Error "Ocurrió un inconveniente al procesar la matriz: $($_.Exception.Message)"
    exit 1
}
