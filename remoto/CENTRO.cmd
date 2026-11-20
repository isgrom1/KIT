@echo off
rem Centro remoto del kit (ventana). El menu de consola es CENTRO_CONSOLA.cmd.
start "" powershell -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0centro_gui.ps1"