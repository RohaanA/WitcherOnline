# =============================================================================
# WitcherOnline Co-op  —  Distribution Builder
# =============================================================================
# Creates two ready-to-use folders in .\dist\:
#
#   dist\server\      — Java relay server + launch scripts (run on host PC)
#   dist\game\        — Mod files mirroring the Witcher 3 install layout.
#                       Copy the CONTENTS of this folder into your game dir.
#
# Usage:
#   .\build-dist.ps1              # host build  (WO_IS_GUEST = false)
#   .\build-dist.ps1 -Guest       # guest build (WO_IS_GUEST = true)
#   .\build-dist.ps1 -ServerIP "192.168.1.100"   # pre-fill server IP in config
# =============================================================================

param(
    [switch]$Guest,
    [string]$ServerIP   = "YOUR_SERVER_IP",
    [string]$Username   = "Player",
    [int]   $Port       = 40000
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
$root      = $PSScriptRoot
$distDir   = Join-Path $root "dist"
$serverOut = Join-Path $distDir "server"
$gameOut   = Join-Path $distDir "game"

$javaSrc   = Join-Path $root "server\src"
$javaBuild = Join-Path $root "server\build"
$wsFile    = Join-Path $root "witcher\mods\modWitcherOnline\content\scripts\local\spike_marionette.ws"
$modSrc    = Join-Path $root "witcher\mods\modWitcherOnline"
$binSrc    = Join-Path $root "witcher\bin\WitcherOnline"       # contains config.xml
$asiBuilt  = Join-Path $root "client\build\WitcherOnlineClient.asi"

# Java 21 — try common install locations then fall back to PATH
$java21Candidates = @(
    "C:\Program Files\Java\jdk-21.0.11\bin\java.exe",
    "C:\Program Files\Microsoft\jdk-21.0.11.10-hotspot\bin\java.exe",
    "C:\Program Files\Eclipse Adoptium\jdk-21.0.11+9\bin\java.exe"
)
$javacCandidates = @(
    "C:\Program Files\Java\jdk-21.0.11\bin\javac.exe",
    "C:\Program Files\Microsoft\jdk-21.0.11.10-hotspot\bin\javac.exe",
    "C:\Program Files\Eclipse Adoptium\jdk-21.0.11+9\bin\javac.exe"
)

function Find-Exe($candidates, $name) {
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    $found = Get-Command $name -ErrorAction SilentlyContinue
    if ($found) { return $found.Source }
    return $null
}

$javaExe  = Find-Exe $java21Candidates  "java"
$javacExe = Find-Exe $javacCandidates   "javac"

# MSBuild (VS 2022 preferred, fall back to 2019 / Build Tools)
$msbuildCandidates = @(
    "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe",
    "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe",
    "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\MSBuild.exe",
    "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\MSBuild\Current\Bin\MSBuild.exe"
)
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
    $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    if ($vsPath) { $msbuildCandidates = @("$vsPath\MSBuild\Current\Bin\MSBuild.exe") + $msbuildCandidates }
}
$msbuildExe = Find-Exe $msbuildCandidates "MSBuild"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Banner($msg) {
    Write-Host ""
    Write-Host "=== $msg ===" -ForegroundColor Cyan
}

function Ok($msg)   { Write-Host "  [OK]  $msg" -ForegroundColor Green  }
function Warn($msg) { Write-Host "  [!!]  $msg" -ForegroundColor Yellow }
function Fail($msg) { Write-Host "  [XX]  $msg" -ForegroundColor Red; exit 1 }

function New-Dir($path) {
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Force $path | Out-Null
    }
}

# ---------------------------------------------------------------------------
# Step 0 — Clean dist
# ---------------------------------------------------------------------------
Banner "Cleaning dist\"
if (Test-Path $distDir) { Remove-Item -Recurse -Force $distDir }
New-Dir $distDir
New-Dir $serverOut
New-Dir $gameOut
Ok "dist\ ready"

# ---------------------------------------------------------------------------
# Step 1 — Compile Java server
# ---------------------------------------------------------------------------
Banner "Compiling Java relay server"

if (-not $javacExe) { Fail "javac not found. Install JDK 21 and add it to PATH." }
Write-Host "  javac: $javacExe"

New-Dir $javaBuild
& $javacExe -d $javaBuild (Get-ChildItem "$javaSrc\*.java" | ForEach-Object { $_.FullName }) 2>&1
if ($LASTEXITCODE -ne 0) { Fail "javac failed - see errors above." }
Ok "Server compiled  ->  server\build\"

# ---------------------------------------------------------------------------
# Step 2 -- Build C++ DLL  (WitcherOnlineClient.asi)
# ---------------------------------------------------------------------------
Banner "Building C++ DLL  (Release|x64)"

$vcxproj  = Join-Path $root "client\MultiplayerClient.vcxproj"
$cppBuild = Join-Path $root "client\build"
New-Dir $cppBuild

if (-not $msbuildExe) {
    Warn "MSBuild not found - skipping C++ DLL build."
    Warn "Install Visual Studio 2022 with 'Desktop development with C++' workload."
} else {
    Write-Host "  MSBuild: $msbuildExe"
    # Override OutDir -> client\build\ (vcxproj hardcodes a GOG install path).
    # TrackFileAccess=false avoids .tlog dependency issues on machines without
    # a matching PlatformToolset registry entry.
    $msbuildArgs = @(
        $vcxproj,
        "/p:Configuration=Release",
        "/p:Platform=x64",
        "/p:OutDir=$cppBuild\",
        "/p:TrackFileAccess=false",
        "/m",
        "/nologo",
        "/v:minimal"
    )
    & $msbuildExe @msbuildArgs
    if ($LASTEXITCODE -ne 0) {
        Warn "MSBuild returned exit $LASTEXITCODE - check output above."
        Warn "The .asi will be missing from dist\game\ (build manually in Visual Studio)."
    } else {
        Ok "WitcherOnlineClient.asi built  ->  client\build\"
    }
}

# ---------------------------------------------------------------------------
# Step 3 -- Package server folder
# ---------------------------------------------------------------------------
Banner "Packaging dist\server\"

# Copy compiled .class files
$serverClasses = Join-Path $serverOut "classes"
New-Dir $serverClasses
Copy-Item -Recurse "$javaBuild\*" $serverClasses
Ok "Java classes copied"

# Write START SERVER batch script (double-click to run)
$javaForBat = if ($javaExe) { $javaExe } else { "java" }
$startBat = @"
@echo off
title WitcherOnline Relay Server (UDP $Port)
echo ================================================
echo  WitcherOnline Co-op Relay Server
echo  Listening on UDP port $Port
echo  Keep this window open while playing!
echo ================================================
echo.
"$javaForBat" -cp "%~dp0classes" WitcherServer
pause
"@
Set-Content (Join-Path $serverOut "start_server.bat") $startBat -Encoding ASCII
Ok "start_server.bat written"

# Write PowerShell launcher too
$startPs1 = @"
# WitcherOnline Relay Server launcher
`$javaExe = "$javaForBat"
`$classes  = Join-Path `$PSScriptRoot "classes"
Write-Host "Starting WitcherOnline relay server on UDP port $Port..." -ForegroundColor Cyan
Write-Host "Keep this window open while playing!" -ForegroundColor Yellow
Write-Host ""
& `$javaExe -cp `$classes WitcherServer
"@
Set-Content (Join-Path $serverOut "start_server.ps1") $startPs1 -Encoding UTF8
Ok "start_server.ps1 written"

# Write firewall helper (run once as admin)
$fwScript = @"
# Run as Administrator -- opens the UDP port WitcherOnline needs
`$rule = "WitcherOnline UDP $Port"
netsh advfirewall firewall add rule name=`"`$rule`" dir=in action=allow protocol=UDP localport=$Port
if (`$LASTEXITCODE -eq 0) {
    Write-Host "Firewall rule added: `$rule  (UDP $Port inbound)" -ForegroundColor Green
} else {
    Write-Host "netsh failed (exit `$LASTEXITCODE). Try running as Administrator." -ForegroundColor Red
}
"@
Set-Content (Join-Path $serverOut "open_firewall_port.ps1") $fwScript -Encoding UTF8
Ok "open_firewall_port.ps1 written"

# Write a server README
$serverReadme = @"
# WitcherOnline — Relay Server

## First-time setup
1. Run `open_firewall_port.ps1` **as Administrator** (once only).
2. If your friend is connecting over the internet (not same WiFi):
   - Forward **UDP port $Port** in your router settings to this PC.
   - Give your friend your **public IP** (check https://whatismyip.com).
   For same-network play: use your local IP (e.g. 192.168.x.x) — no port-forward needed.

## Starting the server
Double-click `start_server.bat`, OR run:
    powershell -ExecutionPolicy Bypass -File start_server.ps1

Keep the window open the entire play session.

## Stopping
Close the window, or type `stop` in the console.

## Console commands
    list    — show connected players
    stats   — server health counters
    kick <name>  — kick a player
    ban  <name>  — ban a player
    stop         — shut down
"@
Set-Content (Join-Path $serverOut "README.txt") $serverReadme -Encoding ASCII
Ok "README.txt written"

# ---------------------------------------------------------------------------
# Step 4 -- Build WitcherScript mod (host or guest variant)
# ---------------------------------------------------------------------------
Banner "Preparing WitcherScript mod  (Guest=$Guest)"

# Read the spike file
$wsContent = Get-Content $wsFile -Raw -Encoding UTF8
$roleLabel = if ($Guest) { "GUEST" } else { "HOST" }

# Flip the role flag
if ($Guest) {
    $wsContent = $wsContent -replace `
        'function WO_IS_GUEST\(\) : bool \{ return false; \}', `
        'function WO_IS_GUEST() : bool { return true; }'
    Ok "Role flag set -> GUEST (WO_IS_GUEST = true)"
} else {
    # Ensure it's host (in case the source was accidentally left on guest)
    $wsContent = $wsContent -replace `
        'function WO_IS_GUEST\(\) : bool \{ return true; \}', `
        'function WO_IS_GUEST() : bool { return false; }'
    Ok "Role flag set -> HOST (WO_IS_GUEST = false)"
}

# ---------------------------------------------------------------------------
# Step 5 -- Assemble dist\game\ (mirrors Witcher 3 install layout)
# ---------------------------------------------------------------------------
Banner "Assembling dist\game\  (copy CONTENTS into game dir)"

# --- mods\modWitcherOnline ---
$modDest = Join-Path $gameOut "mods\modWitcherOnline"
New-Dir $modDest
Copy-Item -Recurse "$modSrc\*" $modDest -Force

# Overwrite spike_marionette.ws with the role-correct, no-BOM version
$spikeOut = Join-Path $modDest "content\scripts\local\spike_marionette.ws"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($spikeOut, $wsContent, $utf8NoBom)
Ok "mods\modWitcherOnline\  ($roleLabel build, no-BOM spike)"

# --- bin\WitcherOnline\config.xml ---
$configDest = Join-Path $gameOut "bin\WitcherOnline"
New-Dir $configDest

# Write a fresh config.xml with the provided IP/username/port
$configXml = @"
<?xml version="1.0"?>
<Config>
    <Username>$Username</Username>
    <ServerIP>$ServerIP</ServerIP>
    <Port>$Port</Port>
</Config>
"@
Set-Content (Join-Path $configDest "config.xml") $configXml -Encoding UTF8
Ok "bin\WitcherOnline\config.xml  (ServerIP=$ServerIP, Port=$Port)"

# --- bin\x64\ and bin\x64_dx12\  (.asi DLL) ---
if (Test-Path $asiBuilt) {
    foreach ($binDir in @("bin\x64", "bin\x64_dx12")) {
        $dest = Join-Path $gameOut $binDir
        New-Dir $dest
        Copy-Item $asiBuilt (Join-Path $dest "WitcherOnlineClient.asi") -Force
    }
    Ok "WitcherOnlineClient.asi  ->  bin\x64\ + bin\x64_dx12\"
} else {
    Warn "WitcherOnlineClient.asi not found (build the C++ DLL first)."
    Warn "Expected: $asiBuilt"
    Warn "Once built, copy it manually to:"
    Warn "   <game>\bin\x64\WitcherOnlineClient.asi"
    Warn "   <game>\bin\x64_dx12\WitcherOnlineClient.asi"

    # Write a placeholder reminder in the game folder
    foreach ($binDir in @("bin\x64", "bin\x64_dx12")) {
        $dest = Join-Path $gameOut $binDir
        New-Dir $dest
        Set-Content (Join-Path $dest "PUT_WitcherOnlineClient_asi_HERE.txt") `
            "Copy WitcherOnlineClient.asi here (built from client\MultiplayerClient.sln)" `
            -Encoding ASCII
    }
}

# --- game README ---
$gameReadme = @"
# WitcherOnline Co-op — Mod Files  [$roleLabel build]

## How to install
Copy the CONTENTS of this folder into your Witcher 3 game directory.
Your game directory looks like:
    C:\...\steamapps\common\The Witcher 3\

After copying you should have:
    <game>\mods\modWitcherOnline\...
    <game>\bin\WitcherOnline\config.xml
    <game>\bin\x64\WitcherOnlineClient.asi
    <game>\bin\x64_dx12\WitcherOnlineClient.asi

## config.xml  (edit before launching)
Located at:  <game>\bin\WitcherOnline\config.xml

    HOST  ->  set ServerIP to 127.0.0.1
    GUEST ->  set ServerIP to the host's IP address

## Steam launch options  (REQUIRED for both players)
Add this to Witcher 3 in Steam -> Properties -> Launch Options:
    -net -debugscripts

## Role: $roleLabel
This package was built for the $roleLabel.
$(if ($Guest) { "You will see the host NPCs as synced marionettes." } else { "Your NPCs are authoritative - the guest mirrors them." })

## Merge input.settings
The mod adds keybindings. Merge the contents of:
    mods\modWitcherOnline\input.settings.txt
into your game's  Documents\The Witcher 3\input.settings
(add any missing sections/lines — don't replace the whole file).
"@
Set-Content (Join-Path $gameOut "README.txt") $gameReadme -Encoding ASCII
Ok "game\README.txt written"

# ---------------------------------------------------------------------------
# Done — summary
# ---------------------------------------------------------------------------
Banner "Build complete!"
Write-Host ""
Write-Host "  dist\server\      <- Run start_server.bat on the HOST PC" -ForegroundColor White
Write-Host "  dist\game\        <- Copy contents into Witcher 3 game dir  [$roleLabel]" -ForegroundColor White
Write-Host ""

# Show tree
Write-Host "  dist\" -ForegroundColor DarkGray
Get-ChildItem $distDir -Recurse | ForEach-Object {
    $rel   = $_.FullName.Substring($distDir.Length + 1)
    $depth = ($rel.Split('\').Count - 1)
    $pad   = "  " + ("  " * $depth)
    $icon  = if ($_.PSIsContainer) { "[+]" } else { "   " }
    Write-Host "$pad$icon $($_.Name)" -ForegroundColor DarkGray
}
Write-Host ""
