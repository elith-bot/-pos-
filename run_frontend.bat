@echo off
title Flutter App
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Requesting Administrator privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)
echo Starting Flutter Application as Administrator...
cd /d "%~dp0frontend"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\check_frontend.ps1"
if errorlevel 20 goto port_busy
if errorlevel 10 goto already_running
call flutter run -d chrome --web-port=51168 --no-web-resources-cdn
pause
exit /b

:already_running
echo Opening the running application: http://localhost:51168
start "" "http://localhost:51168"
exit /b 0

:port_busy
echo The local address is occupied or is not responding.
echo Close the previous Flutter run with q, then start this file again.
pause
exit /b 1
