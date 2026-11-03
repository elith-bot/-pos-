@echo off
title Flutter App
echo Starting Flutter Application...
cd /d "%~dp0frontend"
call flutter run -d chrome --web-port=51168 --no-web-resources-cdn
pause
