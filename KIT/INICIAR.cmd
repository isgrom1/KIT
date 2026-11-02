@echo off
setlocal EnableExtensions DisableDelayedExpansion
title KIT SERVICIO
rem ---------------------------------------------------------------------------
rem  KIT SERVICIO - abre la interfaz grafica y deja este menu de consola de respaldo.
rem  Todas las rutas salen de %~dp0, la carpeta de este archivo: la letra del USB
rem  cambia en cada equipo y, al elevar, el directorio actual pasa a System32.
rem  Este archivo va sin tildes: cmd lo lee con la pagina de codigos OEM.
rem ---------------------------------------------------------------------------
set "KIT=%~dp0"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
rem Desde un proceso de 32 bits, System32 se redirige: Sysnative llega al PowerShell de 64.
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" (
    echo.
    echo  No se encontro Windows PowerShell 5.1 en este equipo.
    pause
    exit /b 1
)

rem fltmc solo responde cuando hay permisos de administrador.
set "ADMIN=NO"
fltmc >nul 2>&1 && set "ADMIN=SI"
rem Al relanzar como admin desde un diagnostico se vuelve directo a esa medicion.
set "MOMENTO=Antes"
if /i "%~1"=="antes" goto diagnostico
if /i "%~1"=="consola" goto menu

rem Interfaz grafica (WPF). Si PowerShell esta restringido o WPF no carga, kit.ps1 sale con 10
rem y se usa este menu de consola. "INICIAR.cmd consola" va directo al menu.
echo.
echo  Abriendo la interfaz grafica... (esta ventana queda de respaldo; no la cierres)
start "" /wait "%PS%" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File "%KIT%scripts\gui\kit.ps1"
if errorlevel 10 if not errorlevel 11 goto sinGui
exit /b 0

:sinGui
echo.
echo  No se pudo abrir la interfaz grafica: PowerShell esta restringido en este equipo
echo  (AppLocker, WDAC o Smart App Control) o falta WPF. Se usa el menu de consola.
pause
if /i "%~1"=="despues" (
    set "MOMENTO=Despues"
    goto diagnostico
)

:menu
rem Sincronizar solo aparece en los equipos del tecnico (config.json: equipos_tecnico).
if not defined TECNICO (
    set "TECNICO=NO"
    "%PS%" -NoProfile -ExecutionPolicy Bypass -File "%KIT%scripts\sincronizar.ps1" -EsTecnico >nul 2>&1 && set "TECNICO=SI"
)
cls
echo.
echo  ==========================================================
echo   KIT SERVICIO                              Admin: %ADMIN%
echo  ==========================================================
echo.
echo   1) Diagnostico ANTES del trabajo
echo   2) Diagnostico DESPUES del trabajo
echo   3) Ficha del cliente
echo   4) Trabajo segun el motivo (calor, lento, archivos, revision)
echo   5) Abrir herramientas
echo   6) Salir
if "%TECNICO%%ADMIN%"=="NOSI" goto menuTeclas
echo.
if "%TECNICO%"=="SI" echo   S) Sincronizar expedientes con el maestro de este PC
if "%ADMIN%"=="NO" echo   A) Relanzar como administrador
:menuTeclas
echo.
rem choice lee una sola tecla: nada de texto libre que pueda romper un "if" con comillas. Las
rem teclas cambian segun el equipo, asi que se traduce el numero que devuelve a la tecla elegida.
set "TECLAS=123456"
if "%TECNICO%"=="SI" set "TECLAS=%TECLAS%S"
if "%ADMIN%"=="NO" set "TECLAS=%TECLAS%A"
choice /c %TECLAS% /n /m "  Opcion: "
if errorlevel 255 goto fin
if not errorlevel 1 goto menu
set /a "IDX=%ERRORLEVEL%-1"
call set "TECLA=%%TECLAS:~%IDX%,1%%"
if "%TECLA%"=="1" goto antes
if "%TECLA%"=="2" goto despues
if "%TECLA%"=="3" goto ficha
if "%TECLA%"=="4" goto trabajo
if "%TECLA%"=="5" goto herramientas
if "%TECLA%"=="6" goto fin
if /i "%TECLA%"=="S" goto sincronizar
if /i "%TECLA%"=="A" goto elevar
goto menu

:antes
set "MOMENTO=Antes"
goto diagnostico

:despues
set "MOMENTO=Despues"
goto diagnostico

:diagnostico
echo.
echo   Diagnostico %MOMENTO% del trabajo
if "%ADMIN%"=="SI" goto opciones
echo   Sin admin quedan incompletos: SMART de discos y discos.txt, BitLocker, TPM,
echo   clave OEM, hypervisorlaunchtype, tareas protegidas y tiempo de arranque.
choice /c SN /n /m "  Relanzar como administrador antes de diagnosticar? [S/N] "
if errorlevel 2 goto opciones
set "KIT_ARG=%MOMENTO%"
goto elevar

:opciones
set "ARGS=-Momento %MOMENTO%"
choice /c SN /n /m "  Incluir recorrido de carpetas (hasta 3 min mas)? [S/N] "
if errorlevel 2 set "ARGS=%ARGS% -SinEspacio"
choice /c SN /n /m "  Abrir resumen.txt al terminar? [S/N] "
if errorlevel 2 goto correr
set "ARGS=%ARGS% -AbrirResumen"
:correr
echo.
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%KIT%scripts\diagnostico.ps1" %ARGS%
set "CODIGO=%ERRORLEVEL%"
echo.
if "%CODIGO%"=="0" goto finDiagnostico
if "%CODIGO%"=="4" (
    echo   No hay un diagnostico ANTES abierto para este equipo: corre primero la opcion 1.
    goto finDiagnostico
)
if "%CODIGO%"=="3" (
    echo   PowerShell esta en modo restringido en este equipo ^(AppLocker, WDAC o Smart App Control^).
    echo   El diagnostico no puede correr aqui. No desactives la seguridad del cliente.
    goto finDiagnostico
)
echo   El diagnostico termino con codigo %CODIGO%. Revisa el mensaje de arriba.
:finDiagnostico
pause
goto menu

:ficha
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%KIT%scripts\ficha.ps1"
pause
goto menu

:trabajo
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%KIT%scripts\trabajo.ps1"
pause
goto menu

:herramientas
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%KIT%scripts\herramientas.ps1"
goto menu

:sincronizar
echo.
echo   Copia los expedientes del USB al maestro sin borrar ni pisar nada.
set "ARGS="
choice /c SN /n /m "  Despues, dejar en el USB solo las atenciones abiertas? [S/N] "
if errorlevel 2 goto correrSync
set "ARGS=-LiberarUsb"
:correrSync
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%KIT%scripts\sincronizar.ps1" %ARGS%
pause
goto menu

:elevar
echo.
echo   Acepta el aviso de Windows (UAC): el kit se abre en una ventana nueva.
set "KIT_CMD=%~f0"
"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "try { if ($env:KIT_ARG) { Start-Process -FilePath $env:KIT_CMD -ArgumentList $env:KIT_ARG -Verb RunAs -ErrorAction Stop } else { Start-Process -FilePath $env:KIT_CMD -Verb RunAs -ErrorAction Stop } } catch { exit 1 }"
if errorlevel 1 goto noElevado
exit /b 0

:noElevado
set "KIT_ARG="
echo   No se elevo: se cancelo el aviso o este usuario no es administrador.
pause
goto menu

:fin
endlocal
exit /b 0
