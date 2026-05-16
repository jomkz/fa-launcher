<#
.SYNOPSIS
    Compatibility launcher for Jane's Fighters Anthology (1998) on modern Windows.

.DESCRIPTION
    Three modes:
      -Info   : Show FA.EXE PE header info and SHA-256 hash.
      -Setup  : Drop manifest and dgVoodoo.conf. Optionally copy LIB files from disc.
      -Launch : Start the game pinned to a single CPU core.

.PARAMETER Setup
    One-time setup. Drops config files and (optionally) copies LIB files from disc.

.PARAMETER Launch
    Launch the game with single-core CPU affinity.

.PARAMETER Info
    Print PE header fields and SHA-256 of the specified EXE.

.PARAMETER GameDir
    Path to the Fighters Anthology install directory.
    Default: C:\JANES\Fighters Anthology

.PARAMETER Exe
    EXE filename within GameDir to operate on.
    Default: FA.EXE

.PARAMETER Disk
    Used with -Setup. One or more paths to mounted FA discs (e.g. E:) or ISO
    files. Accepts multiple values -- pass both discs in a single setup run.
    The setup will copy any real LIB files found on each source into the game
    directory, fixing crashes on certain in-game screens.

.EXAMPLE
    .\fa-launcher.ps1 -Info
    .\fa-launcher.ps1 -Setup -Disk "C:\ISOs\FA_Blue.iso","C:\ISOs\FA_Red.iso"
    .\fa-launcher.ps1 -Setup -Disk E:,F:
    .\fa-launcher.ps1 -Launch
#>
param(
    [switch]$Setup,
    [switch]$Launch,
    [switch]$Info,
    [string]$GameDir  = "C:\JANES\Fighters Anthology",
    [string]$Exe      = "",
    [string[]]$Disk   = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# LIB files the installer leaves as 1-byte stubs in the game directory.
# The startup CD check only needs them to exist on X: (satisfied by fake CD stubs).
# At runtime the game reads them from the game directory -- they must be real files.
$StubLibNames = @('FA_10.LIB','FA_10B.LIB','FA_11.LIB','FA_11B.LIB','FA_4C.LIB','FA_7.LIB')

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Read-UInt16LE([byte[]]$bytes, [int]$offset) {
    [BitConverter]::ToUInt16($bytes, $offset)
}

function Read-UInt32LE([byte[]]$bytes, [int]$offset) {
    [BitConverter]::ToUInt32($bytes, $offset)
}

function Get-FileHash256([byte[]]$bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha.ComputeHash($bytes)
    $sha.Dispose()
    [BitConverter]::ToString($hash).Replace('-', '').ToLower()
}

function Get-PEInfo([byte[]]$bytes) {
    $info = [PSCustomObject]@{
        Valid                = $false
        Machine              = 0
        Timestamp            = 0
        Characteristics      = 0
        Magic                = 0
        ImageBase            = 0
        SizeOfImage          = 0
        Checksum             = 0
        Subsystem            = 0
        DllCharacteristics   = 0
        IsLargeAddressAware  = $false
        Is32Bit              = $false
    }

    if ($bytes.Length -lt 0x40) { return $info }
    if ($bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) { return $info }  # MZ

    $peOff = Read-UInt32LE $bytes 0x3C
    if ($peOff + 96 -gt $bytes.Length) { return $info }

    if ($bytes[$peOff]   -ne 0x50 -or  # P
        $bytes[$peOff+1] -ne 0x45 -or  # E
        $bytes[$peOff+2] -ne 0x00 -or
        $bytes[$peOff+3] -ne 0x00) { return $info }

    $info.Machine            = Read-UInt16LE $bytes ($peOff + 4)
    $info.Timestamp          = Read-UInt32LE $bytes ($peOff + 8)
    $info.Characteristics    = Read-UInt16LE $bytes ($peOff + 22)
    $info.Magic              = Read-UInt16LE $bytes ($peOff + 24)

    if ($info.Magic -ne 0x010B) { return $info }  # PE32 only

    $info.SizeOfImage        = Read-UInt32LE $bytes ($peOff + 80)
    $info.Checksum           = Read-UInt32LE $bytes ($peOff + 88)
    $info.ImageBase          = Read-UInt32LE $bytes ($peOff + 52)
    $info.Subsystem          = Read-UInt16LE $bytes ($peOff + 92)
    $info.DllCharacteristics = Read-UInt16LE $bytes ($peOff + 94)

    $info.IsLargeAddressAware = ($info.Characteristics -band 0x0020) -ne 0
    $info.Is32Bit             = ($info.Characteristics -band 0x0100) -ne 0
    $info.Valid               = $true
    return $info
}

function Get-StubLibs([string]$gameDir) {
    $stubs = @()
    foreach ($name in $StubLibNames) {
        $path = Join-Path $gameDir $name
        if ((Test-Path $path) -and (Get-Item $path).Length -le 1) {
            $stubs += $name
        }
    }
    return $stubs
}

# ---------------------------------------------------------------------------
# -Info
# ---------------------------------------------------------------------------

function Invoke-Info([string]$exePath) {
    if (-not (Test-Path $exePath)) {
        Write-Error "File not found: $exePath"
        exit 1
    }

    $bytes  = [IO.File]::ReadAllBytes($exePath)
    $hash   = Get-FileHash256 $bytes
    $pe     = Get-PEInfo $bytes

    Write-Host ""
    Write-Host "File:     $exePath"
    Write-Host "Size:     $($bytes.Length) bytes"
    Write-Host "SHA-256:  $hash"

    if (-not $pe.Valid) {
        Write-Host "PE:       INVALID (not a PE32 executable)"
        return
    }

    $machineStr = if ($pe.Machine -eq 0x014C) { "i386" } else { "0x{0:X4}" -f $pe.Machine }
    $subsysStr  = switch ($pe.Subsystem) { 2 { "Win32 GUI" } 3 { "Console" } default { "$($pe.Subsystem)" } }
    $ts         = [DateTimeOffset]::FromUnixTimeSeconds($pe.Timestamp).ToString("yyyy-MM-dd HH:mm:ss UTC")

    Write-Host "Machine:  $machineStr"
    Write-Host "Built:    $ts"
    Write-Host "Subsys:   $subsysStr"
    Write-Host ("Chars:    0x{0:X4}" -f $pe.Characteristics)
    Write-Host "  LARGE_ADDRESS_AWARE: $(if ($pe.IsLargeAddressAware) { 'YES' } else { 'NO' })"
    Write-Host "  32BIT_MACHINE:       $(if ($pe.Is32Bit) { 'YES' } else { 'NO' })"
    Write-Host ""
}

# ---------------------------------------------------------------------------
# -Setup [-Disk]
# ---------------------------------------------------------------------------

function Invoke-CopyLibs([string]$diskSource, [string]$gameDir) {
    # Determine if the source is an ISO file or an already-mounted drive path.
    $isoMounted  = $false
    $isoPath     = $null
    $searchRoot  = $diskSource

    if ($diskSource -match '\.iso$') {
        if (-not (Test-Path $diskSource)) {
            Write-Error "ISO file not found: $diskSource"
            exit 1
        }
        Write-Host "Mounting ISO: $diskSource"
        $img        = Mount-DiskImage -ImagePath $diskSource -PassThru
        $driveLetter = ($img | Get-Volume).DriveLetter
        $searchRoot  = "${driveLetter}:\"
        $isoMounted  = $true
        $isoPath     = $diskSource
        Write-Host "Mounted as $driveLetter`:"
    }

    Write-Host ""
    Write-Host "Copying LIB files from $searchRoot ..."
    Write-Host ""

    $copied   = 0
    $skipped  = @()

    try {
        foreach ($name in $StubLibNames) {
            # Search case-insensitively -- disc file systems vary.
            $src = Get-ChildItem $searchRoot -Filter $name -ErrorAction SilentlyContinue |
                   Select-Object -First 1

            if ($src -and $src.Length -gt 1) {
                $dst = Join-Path $gameDir $name.ToUpper()
                Copy-Item -Path $src.FullName -Destination $dst -Force
                Write-Host ("[OK]    {0,-12}  {1,10} bytes" -f $name, $src.Length)
                $copied++
            } else {
                $skipped += $name
            }
        }
    } finally {
        if ($isoMounted) {
            Dismount-DiskImage -ImagePath $isoPath | Out-Null
            Write-Host ""
            Write-Host "Unmounted ISO."
        }
    }

    Write-Host ""
    Write-Host "Copied $copied of $($StubLibNames.Count) LIB files."

    if ($skipped.Count -gt 0) {
        Write-Host ""
        Write-Host "Not found on this disc: $($skipped -join ', ')"
        Write-Host "These may be on the other disc -- run -Setup -Disk again with that disc."
    }
    Write-Host ""
}

function Invoke-Setup([string]$gameDir, [string]$exeName, [string[]]$diskSources) {
    $exePath = Join-Path $gameDir $exeName

    if (-not (Test-Path $exePath)) {
        Write-Error "EXE not found: $exePath"
        exit 1
    }

    Write-Host ""
    Write-Host "=== fa-launcher setup ==="
    Write-Host ""

    # 1. Manifest
    $manifestSrc = Join-Path $ScriptDir "assets\FA.EXE.manifest"
    $manifestDst = Join-Path $gameDir ($exeName + ".manifest")
    Copy-Item -Path $manifestSrc -Destination $manifestDst -Force
    Write-Host "[OK]    Manifest written  ->  $manifestDst"

    # 2. dgVoodoo.conf
    $confSrc = Join-Path $ScriptDir "assets\dgVoodoo.conf"
    $confDst = Join-Path $gameDir "dgVoodoo.conf"
    Copy-Item -Path $confSrc -Destination $confDst -Force
    Write-Host "[OK]    dgVoodoo.conf written  ->  $confDst"

    # 3. LIB files from disc (optional)
    if ($diskSources.Count -gt 0) {
        foreach ($src in $diskSources) {
            Write-Host ""
            Invoke-CopyLibs $src $gameDir
        }
    } else {
        $stubs = Get-StubLibs $gameDir
        if ($stubs.Count -gt 0) {
            Write-Host ""
            Write-Host "Warning: $($stubs.Count) LIB file(s) are missing real content:"
            $stubs | ForEach-Object { Write-Host "  $_" }
            Write-Host "  Certain in-game screens will crash until these are replaced."
            Write-Host "  Re-run setup with your FA ISOs:"
            Write-Host "    .\fa-launcher.ps1 -Setup -Disk `"C:\ISOs\FA_Blue.iso`",`"C:\ISOs\FA_Red.iso`""
        }
    }

    Write-Host ""
    Write-Host "Next steps:"
    Write-Host "  1. Download dgVoodoo2: http://dege.freeweb.hu/dgVoodoo2/dgVoodoo2/"
    Write-Host "     From the archive copy  MS\x86\DDraw.dll  into:"
    Write-Host "       $gameDir\"
    Write-Host "  2. Download dsoal: https://github.com/kcat/dsoal/releases"
    Write-Host "     From the x86 folder copy  dsound.dll  and  dsoal-aldrv.dll  into:"
    Write-Host "       $gameDir\"
    Write-Host "  3. Launch with:  .\fa-launcher.ps1 -Launch"
    Write-Host ""
}

# ---------------------------------------------------------------------------
# -Launch
# ---------------------------------------------------------------------------

function Invoke-Launch([string]$gameDir, [string]$exeName) {
    $exePath = Join-Path $gameDir $exeName
    if (-not (Test-Path $exePath)) {
        Write-Error "EXE not found: $exePath`nRun -Setup first."
        exit 1
    }

    # Warn if any LIB files are still stubs -- certain screens will crash.
    $stubs = Get-StubLibs $gameDir
    if ($stubs.Count -gt 0) {
        Write-Host ""
        Write-Host "Warning: $($stubs.Count) LIB file(s) are 1-byte stubs -- some in-game screens will crash:"
        $stubs | ForEach-Object { Write-Host "  $_" }
        Write-Host "  Fix: .\fa-launcher.ps1 -Setup -Disk E:  (or path to ISO)"
        Write-Host ""
    }

    # Mount a fake CD as X: so FA finds the stub LIB files it checks for at startup.
    # These 1-byte stubs satisfy the existence check only -- real content is read
    # from the game directory, not from X:.
    $fakeCdDir = Join-Path $env:TEMP "fa-fakecd"
    $null = New-Item -ItemType Directory -Path $fakeCdDir -Force
    foreach ($lib in $StubLibNames) {
        $libPath = Join-Path $fakeCdDir $lib
        if (-not (Test-Path $libPath)) {
            [IO.File]::WriteAllBytes($libPath, @(0))
        }
    }

    $substActive = $false
    if (Test-Path 'X:\') {
        Write-Host "Warning: X: is already mapped. FA may use the existing drive."
    } else {
        subst X: $fakeCdDir
        $substActive = $true
        Write-Host "Mounted fake CD: X: -> $fakeCdDir"
    }

    Push-Location $gameDir
    try {
        # /affinity 1 pins to core 0 at creation time -- more reliable than
        # setting ProcessorAffinity after launch.
        $proc = Start-Process -FilePath "cmd.exe" `
            -ArgumentList "/c start /wait /affinity 1 `"Fighters Anthology`" `"$exeName`"" `
            -PassThru
        Write-Host "Started $exeName pinned to core 0"
        if ($proc) { $proc.WaitForExit() }
    } finally {
        Pop-Location
        if ($substActive) {
            subst X: /D
            Write-Host "Unmounted X:"
        }
    }
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

if (-not ($Setup -or $Launch -or $Info)) {
    Write-Host ""
    Write-Host "fa-launcher -- Jane's Fighters Anthology compatibility launcher"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  .\fa-launcher.ps1 -Info   [-GameDir <path>] [-Exe <name>]"
    Write-Host "  .\fa-launcher.ps1 -Setup  [-GameDir <path>] [-Exe <name>] [-Disk <drive-or-iso>]"
    Write-Host "  .\fa-launcher.ps1 -Launch [-GameDir <path>] [-Exe <name>]"
    Write-Host ""
    Write-Host "Defaults:"
    Write-Host "  GameDir : C:\JANES\Fighters Anthology"
    Write-Host "  Exe     : FA.EXE"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\fa-launcher.ps1 -Setup -Disk E:"
    Write-Host "  .\fa-launcher.ps1 -Setup -Disk `"C:\ISOs\FA_Red.iso`""
    Write-Host ""
    exit 0
}

if ($Info) {
    $exeName = if ($Exe) { $Exe } else { "FA.EXE" }
    Invoke-Info (Join-Path $GameDir $exeName)
}

if ($Setup) {
    $exeName = if ($Exe) { $Exe } else { "FA.EXE" }
    Invoke-Setup $GameDir $exeName $Disk
}


if ($Launch) {
    $exeName = if ($Exe) { $Exe } else { "FA.EXE" }
    Invoke-Launch $GameDir $exeName
}
