# Builds the folder (and zip) players get: the game, the Godot runtime that runs it, and the
# importer that turns their own Pokémon X dump into the game's assets. No Nintendo files inside.
#
#   powershell -ExecutionPolicy Bypass -File package\build.ps1
#
# Output: dist\PokemonMegaMMO\ and dist\PokemonMegaMMO.zip
#
# Why not an exported .exe: the game loads models converted from the player's own dump (DAE files),
# and only Godot's editor build can import those. So the package ships that build and runs the
# project folder with it (Play.bat), which is the same thing players would get from an export.
param(
    [string]$Godot = "D:\Tools\Godot\Godot_v4.7.2-stable_win64.exe",
    [string]$GodotConsole = "D:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe",
    [string]$Spica = "D:\Tools\SPICA"
)
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$out = Join-Path $root "dist\PokemonMegaMMO"
# Empty the folder rather than delete it (a shell or Explorer window may be sitting in it).
if (Test-Path $out) { Get-ChildItem $out -Force | Remove-Item -Recurse -Force }
New-Item -ItemType Directory -Force "$out\godot", "$out\importer", "$out\game" | Out-Null

# The Godot runtime (MIT license).
Copy-Item $Godot "$out\godot\Godot.exe"
Copy-Item $GodotConsole "$out\godot\Godot_console.exe"

# The importer: BchTool (ours) + SPICA (public domain).
Copy-Item "$Spica\BchTool.exe", "$Spica\SPICA.dll" "$out\importer\"

# The game: the client project without dev-only folders. The asset cache is made by Import.bat.
$skip = @("asset-cache", ".godot", "tests")
Get-ChildItem (Join-Path $root "client") -Force | Where-Object { $skip -notcontains $_.Name } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path "$out\game" $_.Name) -Recurse }
if (-not (Test-Path "$out\game\addons\colyseus")) {
    throw "client\addons\colyseus is missing: run client\tools\install-colyseus.ps1 first"
}

Copy-Item "$PSScriptRoot\Import.bat", "$PSScriptRoot\Play.bat", "$PSScriptRoot\README.txt" $out

$zip = Join-Path $root "dist\PokemonMegaMMO.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path $out -DestinationPath $zip
"built $out"
"zipped $zip ({0:N0} MB)" -f ((Get-Item $zip).Length / 1MB)
