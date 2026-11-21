@echo off
rem Diagnostico para Isaac: doble clic. Primero se comprueba que el paquete es de Isaac y despues se pide admin.
cd /d "%~dp0"
if /i "%~1"=="/admin" goto admin
powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0motor\bienvenida.ps1" -Modo Diagnostico
if errorlevel 1 pause
exit /b
:admin
net session >nul 2>&1
if errorlevel 1 (
  echo Falta el permiso de administrador: vuelve a abrir DIAGNOSTICO.cmd.
  pause
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0motor\remoto.ps1" -Codigo "%~2" -Consentimiento "%~3"
echo.
pause
