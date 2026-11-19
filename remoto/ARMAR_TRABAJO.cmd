@echo off
rem Arma un paquete de trabajo remoto: arrastra sobre este icono la CARPETA que dejo ABRIR_KITDIAG.cmd
if "%~1"=="" (
  echo Arrastra sobre este icono la carpeta del diagnostico ya abierto
  echo ^(la que quedo al lado del .kitdiag, con el mismo nombre^).
  echo.
  pause
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0armar_trabajo.ps1" -Carpeta "%~1"
echo.
pause