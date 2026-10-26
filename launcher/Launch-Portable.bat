@echo off
if exist "%~dp0MarvelHeroesLauncher.exe" (
  start "" "%~dp0MarvelHeroesLauncher.exe" %*
  exit /b
)
where pwsh.exe >nul 2>nul
if errorlevel 1 (
  echo Install PowerShell 7 for Windows, then run this launcher again.
  pause
  exit /b 1
)
pwsh.exe -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0Play.ps1"
if errorlevel 1 pause
