@echo off
rem Trabajo de Isaac: doble clic, aceptar el permiso de administrador y seguir las instrucciones.
cd /d "%~dp0"
net session >nul 2>&1
if errorlevel 1 (
  echo Pidiendo permiso de administrador...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0motor\trabajo.ps1" %*
echo.
pause