@echo off
rem Starts Pokemon Mega MMO.
cd /d "%~dp0"
if not exist "game\asset-cache\maps\map01" (
  echo The game's assets aren't there yet. Run Import.bat first, with your own Pokemon X dump.
  pause
  exit /b 1
)
start "" godot\Godot.exe --path game
