# Downloads the Colyseus Godot SDK into client/addons/colyseus (ignored by git; ~100 MB, all platforms).
param([string]$Version = "0.18.3")

$client = Split-Path $PSScriptRoot -Parent
$url = "https://github.com/colyseus/native-sdk/releases/download/godot-v$Version/colyseus-godot-$Version.zip"
$tmp = Join-Path ([IO.Path]::GetTempPath()) "colyseus-godot-$Version"
New-Item -ItemType Directory -Force $tmp | Out-Null

Write-Host "Downloading Colyseus Godot SDK $Version..."
Invoke-WebRequest -UseBasicParsing $url -OutFile "$tmp\sdk.zip"
Expand-Archive "$tmp\sdk.zip" "$tmp\x" -Force
$addon = Get-ChildItem "$tmp\x" -Recurse -Directory -Filter colyseus | Where-Object { $_.Parent.Name -eq "addons" } | Select-Object -First 1
if (-not $addon) { throw "addons/colyseus not found in the zip" }
New-Item -ItemType Directory -Force "$client\addons" | Out-Null
Remove-Item -Recurse -Force "$client\addons\colyseus" -ErrorAction SilentlyContinue
Copy-Item -Recurse $addon.FullName "$client\addons\colyseus"
Remove-Item -Recurse -Force $tmp
Write-Host "Installed to $client\addons\colyseus"
