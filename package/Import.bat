@echo off
rem Turns YOUR OWN decrypted Pokemon X RomFS into the game's assets (models, maps, text).
rem Usage: double-click and paste the folder, or drag the RomFS folder onto this file.
setlocal
cd /d "%~dp0"
set "ROMFS=%~1"
if "%ROMFS%"=="" (
  echo Pokemon Mega MMO - importer
  echo.
  echo You need a decrypted RomFS dumped from your own Pokemon X cartridge.
  echo It's the folder that contains the "a" folder.
  echo.
  set /p "ROMFS=Paste the RomFS folder path and press Enter: "
)
set "ROMFS=%ROMFS:"=%"
if not exist "%ROMFS%\a\0\0\7" (
  echo.
  echo That folder doesn't look like a Pokemon X RomFS: "%ROMFS%\a\0\0\7" is missing.
  pause
  exit /b 1
)
echo.
echo Converting your game files...
importer\BchTool.exe import "%ROMFS%" game\asset-cache
if errorlevel 1 (
  echo.
  echo The import failed. See the messages above.
  pause
  exit /b 1
)
echo.
echo Preparing the assets for the game. The first time this takes 10-20 minutes - only once...
godot\Godot_console.exe --headless --path game --import >nul 2>&1
echo.
echo All done! Start the game with Play.bat.
pause
