@echo off
rem Abre un .kitdiag (diagnostico o trabajo remoto): arrastra el archivo sobre este icono.
if "%~1"=="" (
  echo Arrastra el archivo .kitdiag sobre este icono ABRIR_KITDIAG.cmd
  echo.
  pause
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0abrir_diagnostico.ps1" -Archivo "%~1"
echo.
pause