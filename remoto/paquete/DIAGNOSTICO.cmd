@echo off
rem Diagnostico para Isaac: doble clic, aceptar el permiso de administrador y esperar.
cd /d "%~dp0"
net session >nul 2>&1
if errorlevel 1 (
  echo Pidiendo permiso de administrador...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0motor\remoto.ps1" %*
echo.
pause
