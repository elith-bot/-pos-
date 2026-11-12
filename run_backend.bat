@echo off
title Python Flask Backend Server
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Requesting Administrator privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)
echo Starting Python Flask Backend as Administrator...
cd /d "%~dp0backend"
python app.py
pause
