# fa-launcher

Compatibility launcher for Jane's Fighters Anthology (1998) on Windows 10/11.

## Prerequisites

- Windows 10 or 11 (64-bit)
- PowerShell 5.1 (ships with Windows -- no install needed)
- Your original Fighters Anthology install (default: `C:\JANES\Fighters Anthology`)
- Your FA disc ISOs (Blue and Red)
- **dgVoodoo2** -- download separately (see Step 2 below)
- **dsoal** -- download separately (see Step 3 below)

## Game Installation Notes

When installing Fighters Anthology, two choices matter:

- **Choose "Full Install - Digital Music"** -- installs music tracks to the hard
  drive so no disc is needed for in-game music playback.
- **Skip the DirectX installation** -- when the installer offers to install
  DirectX, click Next without installing it. FA ships a 1998-era DirectX that
  has no place on a modern Windows system.

## Quick Start

### Step 1 -- Run setup (once)

```powershell
.\fa-launcher.ps1 -Setup -Disk "C:\ISOs\FA_Blue.iso","C:\ISOs\FA_Red.iso"
```

This drops the compatibility config files and copies the required LIB files from
your FA discs into the game directory. Mounted drive letters work too:

```powershell
.\fa-launcher.ps1 -Setup -Disk E:,F:
```

After this step no disc or ISO is needed to play.

### Step 2 -- Install dgVoodoo2 (once)

1. Download dgVoodoo2 from http://dege.freeweb.hu/dgVoodoo2/dgVoodoo2/
2. Open the archive and copy `MS\x86\DDraw.dll` into your FA install directory

### Step 3 -- Install dsoal (once)

dsoal replaces DirectSound with an OpenAL Soft backend so FA's audio works on
Windows 10/11.

1. Download dsoal from https://github.com/kcat/dsoal/releases
2. Open the archive -- it contains separate `x86` and `x64` folders
3. From the **x86 folder**, copy both files into your FA install directory:
   - `dsound.dll`
   - `dsoal-aldrv.dll`

> **Important:** FA.EXE is a 32-bit application. You must use the files from
> the `x86` folder. The `x64` versions have identical filenames but will not
> load and the game will have no audio.

### Step 4 -- Launch

```powershell
.\fa-launcher.ps1 -Launch
```

The launcher maps a fake CD as `X:` before starting the game and removes it on exit.
No physical disc or ISO required.

## All Commands

```powershell
# Show PE header info and SHA-256 hash for FA.EXE
.\fa-launcher.ps1 -Info

# One-time setup -- drops config files and copies LIB files from your FA discs
.\fa-launcher.ps1 -Setup -Disk "C:\ISOs\FA_Blue.iso","C:\ISOs\FA_Red.iso"
.\fa-launcher.ps1 -Setup -Disk E:,F:

# Launch FA.EXE pinned to core 0
.\fa-launcher.ps1 -Launch

# Override game directory
.\fa-launcher.ps1 -Setup  -GameDir "D:\Games\FA" -Disk "C:\ISOs\FA_Blue.iso","C:\ISOs\FA_Red.iso"
.\fa-launcher.ps1 -Launch -GameDir "D:\Games\FA"
```

## What Each Fix Does

**Fake CD drive (X:)**
FA checks for a disc in drive X: at startup before it will run. The launcher
satisfies this by mapping a temporary folder to X: with `subst` just before
launch and removing it when the game exits. No physical disc or ISO is required.
This is the modern equivalent of the old FAKECD TSR utility.

The startup check only cares that six specific files *exist* on X: -- it never
reads their content. The launcher creates 1-byte placeholder files for this
purpose. The game reads actual content from those same-named files in the game
directory instead, which is why `-Setup -Disk` copies the real files there once
during setup.

**dgVoodoo2 (DDraw.dll replacement)**
FA uses the DirectDraw 2D blit API for all rendering. Windows 10/11 ships a
stub ddraw.dll that no longer implements the old palettized surface modes FA
needs. dgVoodoo2 replaces it with a DLL that intercepts DirectDraw calls and
translates them to Direct3D 11, which works on any modern GPU. It also reports
itself as DirectX 7 to satisfy FA's runtime version check.

**dsoal (dsound.dll replacement)**
FA uses Miles Sound System 3.50 (WAIL32.DLL) for audio, which loads DirectSound
at runtime. Windows 10/11's built-in DirectSound no longer supports the hardware
mixing modes that old games relied on, resulting in complete silence. dsoal
replaces dsound.dll with a wrapper that routes audio through OpenAL Soft to
WASAPI, providing full DirectSound compatibility. The x86 (32-bit) build is
required -- FA.EXE is a 32-bit process and cannot load the x64 version.

**Application manifest**
Without a manifest, Windows applies legacy compatibility shims to old
executables that can interfere with DirectDraw surface creation. The manifest
declares Windows 10/11 compatibility (opting out of the shims) and marks the
application as not DPI-aware, which prevents the DWM compositor from scaling
the 640x480 game window up blurry before it reaches the display.

**CPU affinity**
FA's game loop can spin faster than intended on modern multi-core CPUs, causing
audio glitches and CPU pegging. The launcher starts the game via `cmd /c start /affinity 1`,
which pins the process to core 0 at creation time before the first instruction runs.

## Troubleshooting

**"running scripts is disabled on this system"**
PowerShell's execution policy is blocking the script. Run once in an elevated
PowerShell window:
```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

**Script can't find assets\ directory**
Run the script from its own directory, or use the full path:
```powershell
& "$env:USERPROFILE\src\fa-launcher\fa-launcher.ps1" -Setup -Disk "C:\ISOs\FA_Blue.iso","C:\ISOs\FA_Red.iso"
```

**Game still shows "DirectX version" error after setup**
dgVoodoo2's DDraw.dll is not in the game directory. Re-check Step 2.

**Game crashes on certain screens (dead-pilot, briefings, etc.)**
The LIB files were not copied from your FA discs. Re-run setup with both ISOs:
```powershell
.\fa-launcher.ps1 -Setup -Disk "C:\path\to\FA_Blue.iso","C:\path\to\FA_Red.iso"
```

**No audio**
dsoal's dsound.dll is either missing or the wrong version. Re-check Step 3 --
make sure you copied from the `x86` folder, not `x64`.

**Game runs but screen is black**
Set `FullscreenWindowMode = true` in `dgVoodoo.conf` to have dgVoodoo2 render
into a desktop window instead of exclusive fullscreen.
