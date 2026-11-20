@echo off
rem Centro remoto del kit: menu de consola (respaldo de la ventana).
title Centro remoto - KIT SERVICIO
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0centro.ps1"