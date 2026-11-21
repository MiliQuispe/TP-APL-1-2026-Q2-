# Integrantes del grupo:
# Altamiranda Isaias
# Quispe, Milagros 45064110
# Puca, Micaela 39913189
# Penela, Santiago 44254763
# Sabes, Franco 38168884

<#
.SYNOPSIS
Demonio que monitorea un directorio y genera backups
comprimidos cuando detecta archivos duplicados.

.DESCRIPTION
Este script implementa un proceso demonio que monitorea, en
forma recursiva, un directorio y sus subdirectorios utilizando
FileSystemWatcher. Cuando se crea (o se mueve hacia el arbol)
un archivo nuevo que resulta duplicado de otro ya existente
(mismo nombre y mismo tamano, igual criterio que el Ejercicio
3), genera un log y comprime los archivos involucrados en un
archivo zip dentro del directorio de salida, con nombre en
formato yyyyMMdd-HHmmss.

El mismo script permite ademas detener un demonio ya iniciado
sobre un directorio, y evita que se inicien dos demonios sobre
el mismo directorio en forma simultanea.

.PARAMETER directorio
Ruta del directorio a monitorear (obligatorio en ambos modos).
Acepta rutas relativas, absolutas o con espacios.

.PARAMETER salida
Ruta del directorio donde se generan los backups. Obligatorio
al iniciar el demonio.

.PARAMETER kill
Indica que se debe detener el demonio iniciado sobre
-directorio. Solo puede usarse junto con -directorio.

.EXAMPLE
./ejercicio4.ps1 -directorio ../monitor -salida ../salida
Inicia el demonio sobre "../monitor", generando backups en
"../salida".

.EXAMPLE
./ejercicio4.ps1 -directorio ../monitor -kill
Detiene el demonio que este corriendo sobre "../monitor".
#>

[CmdletBinding(DefaultParameterSetName = 'Start')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Start')]
    [Parameter(Mandatory = $true, ParameterSetName = 'Kill')]
    [ValidateNotNullOrEmpty()]
    [string]$directorio,

    [Parameter(Mandatory = $true, ParameterSetName = 'Start')]
    [ValidateNotNullOrEmpty()]
    [string]$salida,

    [Parameter(Mandatory = $true, ParameterSetName = 'Kill')]
    [switch]$kill,

    # Uso interno: indica que ESTA instancia del proceso ES el
    # demonio. No forma parte de la interfaz publica del script.
    [Parameter(Mandatory = $false, ParameterSetName = 'Start')]
    [switch]$Interno
)

$ErrorActionPreference = 'Stop'
# GetTempPath funciona tanto en Windows como en Linux ($env:TEMP
# no existe en Linux)
$script:TempRoot = [System.IO.Path]::GetTempPath()
$script:StateRoot = Join-Path $script:TempRoot 'ejercicio4_daemons'

# ------------------------------------------------------------
# Write-FriendlyError: muestra un mensaje de error comprensible
# para un usuario sin conocimientos tecnicos
# ------------------------------------------------------------
function Global:Write-FriendlyError {
    param([string]$Message)
    Write-Host "Error: $Message" -ForegroundColor Red
}

# ------------------------------------------------------------
# Get-DirectoryHash: obtiene un identificador unico y estable
# (MD5) para una ruta de directorio absoluta
# ------------------------------------------------------------
function Global:Get-DirectoryHash {
    param([string]$Path)
    # Se quita la barra final para que "dir" y "dir/" sean el mismo directorio
    $normalized = $Path.TrimEnd('\', '/').ToLowerInvariant()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
    $hashBytes = [System.Security.Cryptography.MD5]::Create().ComputeHash($bytes)
    -join ($hashBytes | ForEach-Object { $_.ToString('x2') })
}

# ------------------------------------------------------------
# Get-StateFiles: dado un directorio absoluto, devuelve las
# rutas del archivo de PID y del archivo "senal de detencion"
# (stop flag) usados para controlar su demonio
# ------------------------------------------------------------
function Global:Get-StateFiles {
    param([string]$AbsoluteDirectory)
    $hash = Get-DirectoryHash -Path $AbsoluteDirectory
    [PSCustomObject]@{
        PidFile  = Join-Path $script:StateRoot "$hash.pid"
        StopFile = Join-Path $script:StateRoot "$hash.stop"
        ErrFile  = Join-Path $script:StateRoot "$hash.err"
        # Lo crea el demonio cuando ya esta monitoreando
        ReadyFile = Join-Path $script:StateRoot "$hash.ready"
    }
}

# ------------------------------------------------------------
# Test-DaemonRunning: verifica si hay un proceso demonio vivo
# registrado en el archivo de PID indicado
# ------------------------------------------------------------
function Global:Test-DaemonRunning {
    param([string]$PidFile)
    if (-not (Test-Path $PidFile)) { return $false }
    try {
        $storedId = Get-Content $PidFile -ErrorAction Stop
        $null = Get-Process -Id $storedId -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

# ------------------------------------------------------------
# Find-DuplicateFiles: busca, dentro del arbol de un directorio,
# archivos con el mismo nombre y el mismo tamano que el archivo
# nuevo recibido (mismo criterio de duplicado que el Ejercicio 3)
# ------------------------------------------------------------
function Global:Find-DuplicateFiles {
    param(
        [string]$NewFilePath,
        [string]$RootDirectory
    )

    $newItem = Get-Item -LiteralPath $NewFilePath -ErrorAction SilentlyContinue
    if (-not $newItem) { return @() }

    Get-ChildItem -LiteralPath $RootDirectory -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -ne $newItem.FullName -and
            $_.Name -eq $newItem.Name -and
            $_.Length -eq $newItem.Length
        }
}

# ------------------------------------------------------------
# New-BackupArchive: arma una carpeta temporal en el TEMP del
# sistema con copias de los archivos duplicados (preservando su
# ruta relativa al directorio monitoreado), la comprime como
# .zip con nombre yyyyMMdd-HHmmss en el directorio de salida,
# escribe un log y limpia el temporal (try/finally).
# ------------------------------------------------------------
function Global:New-BackupArchive {
    param(
        [System.IO.FileInfo]$NewFile,
        [string]$RootDirectory,
        [string]$OutputDirectory,
        [System.IO.FileInfo[]]$Duplicates
    )

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $tempDir = Join-Path $script:TempRoot "ejercicio4_backup_$timestamp"

    try {
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

        $allFiles = @($NewFile) + $Duplicates
        foreach ($file in $allFiles) {
            $relativePath = $file.FullName.Substring($RootDirectory.Length).TrimStart('\', '/')
            $destination = Join-Path $tempDir $relativePath
            New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
            Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
        }

        $logPath = Join-Path $OutputDirectory "$timestamp.log"
        $zipPath = Join-Path $OutputDirectory "$timestamp.zip"

        $logLines = @(
            "Duplicado detectado: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            "Archivo nuevo: $($NewFile.FullName)"
            "Coincidencias encontradas:"
        ) + ($Duplicates | ForEach-Object { "  - $($_.FullName)" })

        $logLines | Out-File -FilePath $logPath -Encoding utf8

        Compress-Archive -Path (Join-Path $tempDir '*') -DestinationPath $zipPath -Force
    } catch {
        Write-FriendlyError "no se pudo generar el backup: $($_.Exception.Message)"
    } finally {
        if (Test-Path $tempDir) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ------------------------------------------------------------
# Start-DaemonProcess: valida que no exista ya un demonio para
# el mismo directorio, y lanza una nueva instancia oculta de
# este mismo script (en modo -Interno) que queda corriendo
# como demonio, guardando su PID.
# ------------------------------------------------------------
function Global:Start-DaemonProcess {
    param(
        [string]$Directorio,
        [string]$Salida
    )

    $resolved = Resolve-Path -LiteralPath $Directorio -ErrorAction SilentlyContinue
    if (-not $resolved) {
        Write-FriendlyError "el directorio a monitorear '$Directorio' no existe."
        return
    }
    $absDir = $resolved.ProviderPath

    if (-not (Test-Path $Salida)) {
        try { New-Item -ItemType Directory -Path $Salida -Force | Out-Null }
        catch {
            Write-FriendlyError "no se pudo crear el directorio de salida '$Salida'."
            return
        }
    }
    $absOut = (Resolve-Path -LiteralPath $Salida).ProviderPath

    New-Item -ItemType Directory -Path $script:StateRoot -Force -ErrorAction SilentlyContinue | Out-Null
    $state = Get-StateFiles -AbsoluteDirectory $absDir

    if (Test-DaemonRunning -PidFile $state.PidFile) {
        Write-FriendlyError "ya existe un demonio en ejecucion para el directorio '$absDir'."
        return
    }
    Remove-Item -LiteralPath $state.PidFile, $state.StopFile, $state.ReadyFile -ErrorAction SilentlyContinue

    $scriptPath = $PSCommandPath
    # Se relanza con el mismo ejecutable que esta corriendo este
    # script (powershell.exe en Windows, pwsh en Linux)
    $exePath = (Get-Process -Id $PID).Path
    $esWindows = [System.Environment]::OSVersion.Platform -eq 'Win32NT'

    $argumentList = @('-NoLogo', '-NoProfile', '-NonInteractive')
    if ($esWindows) { $argumentList += @('-WindowStyle', 'Hidden') }
    # Una "\" final escaparia la comilla de cierre ("C:\dir\" llega
    # roto al proceso hijo), por eso se duplica
    $quote = { param($s) '"' + ($s -replace '\\$', '\\') + '"' }
    $argumentList += @(
        '-File', (& $quote $scriptPath),
        '-directorio', (& $quote $absDir),
        '-salida', (& $quote $absOut),
        '-Interno'
    )

    $startParams = @{
        FilePath     = $exePath
        ArgumentList = $argumentList
        PassThru     = $true
    }
    if ($esWindows) {
        # -WindowStyle solo existe en Windows
        $startParams.WindowStyle = 'Hidden'
    } else {
        # En Linux se desvincula la salida del demonio de la terminal
        $startParams.RedirectStandardOutput = '/dev/null'
        $startParams.RedirectStandardError  = $state.ErrFile
    }

    $process = Start-Process @startParams

    Set-Content -LiteralPath $state.PidFile -Value $process.Id

    # Se espera a que el demonio confirme que ya esta monitoreando,
    # para no perder archivos creados apenas termina este comando
    $limite = (Get-Date).AddSeconds(30)
    while (-not (Test-Path -LiteralPath $state.ReadyFile)) {
        if ($process.HasExited -or (Get-Date) -gt $limite) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $state.PidFile, $state.ReadyFile -ErrorAction SilentlyContinue
            Write-FriendlyError "el demonio no pudo iniciarse sobre '$absDir'."
            return
        }
        Start-Sleep -Milliseconds 200
    }

    Write-Host "Demonio iniciado correctamente sobre '$absDir' (PID $($process.Id))."
}

# ------------------------------------------------------------
# Stop-DaemonProcess: le pide al demonio asociado al directorio
# indicado que finalice (mediante un archivo "senal") y espera
# a que termine, limpiando su estado.
# ------------------------------------------------------------
function Global:Stop-DaemonProcess {
    param([string]$Directorio)

    $resolved = Resolve-Path -LiteralPath $Directorio -ErrorAction SilentlyContinue
    if (-not $resolved) {
        Write-FriendlyError "el directorio '$Directorio' no existe."
        return
    }
    $absDir = $resolved.ProviderPath
    $state = Get-StateFiles -AbsoluteDirectory $absDir

    if (-not (Test-DaemonRunning -PidFile $state.PidFile)) {
        Write-FriendlyError "no hay ningun demonio en ejecucion para el directorio '$absDir'."
        Remove-Item -LiteralPath $state.PidFile, $state.StopFile, $state.ErrFile -ErrorAction SilentlyContinue
        return
    }

    $storedId = Get-Content $state.PidFile
    New-Item -ItemType File -Path $state.StopFile -Force | Out-Null

    try {
        Wait-Process -Id $storedId -Timeout 5 -ErrorAction Stop
    } catch {
        # Si no termino solo dentro del tiempo de espera, se fuerza la salida
        Stop-Process -Id $storedId -Force -ErrorAction SilentlyContinue
    }

    Remove-Item -LiteralPath $state.PidFile, $state.StopFile, $state.ErrFile, $state.ReadyFile -ErrorAction SilentlyContinue
    Write-Host "Demonio detenido correctamente para el directorio '$absDir'."
}

# ------------------------------------------------------------
# Invoke-NewFile: procesa un archivo nuevo dentro del arbol
# monitoreado; si tiene duplicados (y no fue respaldado antes)
# genera el backup
# ------------------------------------------------------------
function Global:Invoke-NewFile {
    param(
        [string]$FullPath,
        [PSCustomObject]$MessageData
    )

    $rootDir  = $MessageData.RootDirectory
    $outDir   = $MessageData.OutputDirectory
    $backedUp = $MessageData.AlreadyBackedUp

    [System.Threading.Monitor]::Enter($backedUp)
    try {
        if ($backedUp.ContainsKey($FullPath)) { return }
    } finally {
        [System.Threading.Monitor]::Exit($backedUp)
    }

    Start-Sleep -Milliseconds 200  # da tiempo a que el archivo termine de escribirse
    $duplicates = @(Find-DuplicateFiles -NewFilePath $FullPath -RootDirectory $rootDir)
    if ($duplicates.Count -eq 0) { return }

    $newItem = $null
    [System.Threading.Monitor]::Enter($backedUp)
    try {
        # Volvemos a chequear: puede que el otro archivo del
        # par ya haya generado el backup mientras esperabamos.
        if ($backedUp.ContainsKey($FullPath)) { return }
        $newItem = Get-Item -LiteralPath $FullPath -ErrorAction SilentlyContinue
        if (-not $newItem) { return }

        $backedUp[$FullPath] = $true
        foreach ($d in $duplicates) { $backedUp[$d.FullName] = $true }
    } finally {
        [System.Threading.Monitor]::Exit($backedUp)
    }

    New-BackupArchive -NewFile $newItem -RootDirectory $rootDir `
        -OutputDirectory $outDir -Duplicates $duplicates
}

# ------------------------------------------------------------
# Start-MonitorLoop: cuerpo del proceso demonio (corre solo en
# la instancia lanzada con -Interno). Registra el
# FileSystemWatcher y permanece vivo hasta encontrar la senal
# de detencion.
# ------------------------------------------------------------
function Global:Start-MonitorLoop {
    param(
        [string]$Directorio,
        [string]$Salida
    )

    $absDir = (Resolve-Path -LiteralPath $Directorio).ProviderPath
    New-Item -ItemType Directory -Path $script:StateRoot -Force -ErrorAction SilentlyContinue | Out-Null
    $state = Get-StateFiles -AbsoluteDirectory $absDir
    Set-Content -LiteralPath $state.PidFile -Value $PID

    $watcher = New-Object System.IO.FileSystemWatcher
    $watcher.Path = $absDir
    $watcher.IncludeSubdirectories = $true
    $watcher.Filter = '*.*'
    # DirectoryName: para enterarse tambien de carpetas nuevas
    $watcher.NotifyFilter = [System.IO.NotifyFilters]'FileName, DirectoryName'

    $messageData = [PSCustomObject]@{
        RootDirectory   = $absDir
        OutputDirectory = $Salida
        # Registro (thread-safe) de archivos que ya formaron parte
        # de algun backup. Evita procesar el mismo archivo dos
        # veces cuando: (a) FileSystemWatcher dispara el mismo
        # evento mas de una vez para una sola escritura, o (b) los
        # dos archivos de un mismo par duplicado se crean casi al
        # mismo tiempo y cada uno dispara su propio evento.
        AlreadyBackedUp = [System.Collections.Hashtable]::Synchronized(@{})
    }

    # $Event y $EventArgs son variables automaticas que PowerShell
    # define dentro del -Action de Register-ObjectEvent
    $action = {
        $path = $EventArgs.FullPath
        $data = $Event.MessageData

        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Invoke-NewFile -FullPath $path -MessageData $data
        }
        elseif (Test-Path -LiteralPath $path -PathType Container) {
            # Carpeta nueva (o movida al arbol): los archivos creados
            # dentro de ella antes de que el watcher empiece a vigilarla
            # no generan evento propio, asi que se revisan aca
            Start-Sleep -Milliseconds 200
            Get-ChildItem -LiteralPath $path -Recurse -File -ErrorAction SilentlyContinue |
                ForEach-Object { Invoke-NewFile -FullPath $_.FullName -MessageData $data }
        }
    }

    # Se cubren tanto archivos nuevos (Created) como archivos
    # movidos dentro del arbol monitoreado (Renamed).
    $subscriptions = @(
        Register-ObjectEvent -InputObject $watcher -EventName Created -Action $action -MessageData $messageData
        Register-ObjectEvent -InputObject $watcher -EventName Renamed -Action $action -MessageData $messageData
    )
    $watcher.EnableRaisingEvents = $true
    New-Item -ItemType File -Path $state.ReadyFile -Force | Out-Null

    try {
        while (-not (Test-Path $state.StopFile)) {
            Start-Sleep -Seconds 1
        }
    } finally {
        $watcher.EnableRaisingEvents = $false
        foreach ($subscription in $subscriptions) {
            Unregister-Event -SourceIdentifier $subscription.Name -ErrorAction SilentlyContinue
        }
        $watcher.Dispose()
        Remove-Item -LiteralPath $state.PidFile, $state.StopFile, $state.ReadyFile -ErrorAction SilentlyContinue
    }
}

# ============================================================
# Punto de entrada
# ============================================================
try {
    if ($Interno) {
        Start-MonitorLoop -Directorio $directorio -Salida $salida
    }
    elseif ($kill) {
        Stop-DaemonProcess -Directorio $directorio
    }
    else {
        Start-DaemonProcess -Directorio $directorio -Salida $salida
    }
} catch {
    Write-FriendlyError $_.Exception.Message
    exit 1
}
