@echo off
rem Crea el codigo de un cliente para el diagnostico a distancia y copia el mensaje para WhatsApp.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0codigo_cliente.ps1" %*
echo.
pause
