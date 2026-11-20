@echo off
rem Centro remoto del kit: menu para abrir lo que llega, armar trabajos y preparar envios.
title Centro remoto - KIT SERVICIO
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0centro.ps1"