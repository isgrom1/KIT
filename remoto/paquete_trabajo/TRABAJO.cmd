@echo off
rem Trabajo de Isaac: doble clic. Primero se comprueba que el paquete es de Isaac y despues se pide admin.
cd /d "%~dp0"
if /i "%~1"=="/admin" goto admin
powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0motor\bienvenida.ps1" -Modo Trabajo
if errorlevel 1 pause
exit /b
:admin
net session >nul 2>&1
if errorlevel 1 (
  echo Falta el permiso de administrador: vuelve a abrir TRABAJO.cmd.
  pause
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0motor\trabajo.ps1"
echo.
pause
