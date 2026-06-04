# One-shot co-op deploy: WS (host+guest) AND the C++ .asi.
#  - WS: repo -> PC game dir (host, guest=false); guest version (guest=true, no-BOM) -> Downloads stable name
#  - DLL: client\build\WitcherOnlineClient.asi -> PC bin\x64 + bin\x64_dx12, AND -> Downloads (served on :8080)
# Deck pulls both with curl (cache-immune). Run deploy-coop.ps1 after any code change.

$repo    = "C:\Users\kirco\OneDrive\Documents\GitHUb\witcher_server\WitcherOnline\witcher\mods\modWitcherOnline\content\scripts\local\spike_marionette.ws"
$pcGame  = "D:\SteamLibrary\steamapps\common\The Witcher 3\mods\modWitcherOnline\content\scripts\local\spike_marionette.ws"
$dllBuilt= "C:\Users\kirco\OneDrive\Documents\GitHUb\witcher_server\WitcherOnline\client\build\WitcherOnlineClient.asi"
$pcBin1  = "D:\SteamLibrary\steamapps\common\The Witcher 3\bin\x64\WitcherOnlineClient.asi"
$pcBin2  = "D:\SteamLibrary\steamapps\common\The Witcher 3\bin\x64_dx12\WitcherOnlineClient.asi"
$dl      = "C:\Users\kirco\Downloads"

# --- WS ---
Copy-Item $repo $pcGame -Force
$content = Get-Content $repo -Raw
$content = $content -replace 'function WO_IS_GUEST\(\) : bool \{ return false; \}', 'function WO_IS_GUEST() : bool { return true; }'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $dl "spike_marionette.ws"), $content, $utf8NoBom)

# --- DLL ---
$dllOk = Test-Path $dllBuilt
if ($dllOk) {
    Copy-Item $dllBuilt $pcBin1 -Force
    Copy-Item $dllBuilt $pcBin2 -Force
    Copy-Item $dllBuilt (Join-Path $dl "WitcherOnlineClient.asi") -Force
}

# --- report ---
$guest = (Select-String -Path (Join-Path $dl "spike_marionette.ws") -Pattern 'WO_IS_GUEST\(\) : bool \{ return (true|false)' | Select-Object -First 1).Line.Trim()
Write-Output ("WS  PC=host  Deck=" + $guest + "  (no-BOM)")
Write-Output ("DLL built+staged: " + $dllOk)
Write-Output ""
Write-Output "=== DECK: paste in Konsole, then restart game ==="
$base = "/home/deck/.local/share/Steam/steamapps/common/The Witcher 3"
Write-Output ("curl -s http://192.168.0.49:8080/spike_marionette.ws -o `"$base/mods/modWitcherOnline/content/scripts/local/spike_marionette.ws`"")
Write-Output ("curl -s http://192.168.0.49:8080/WitcherOnlineClient.asi -o `"$base/bin/x64/WitcherOnlineClient.asi`"")
Write-Output ("curl -s http://192.168.0.49:8080/WitcherOnlineClient.asi -o `"$base/bin/x64_dx12/WitcherOnlineClient.asi`"")
