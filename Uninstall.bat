@echo off
rem Houston - removes this PC's shortcuts (and any Apollo tasks in Task Scheduler).
rem The miner itself is not changed. "Uninstall.bat /text" skips the window.
setlocal
title Houston - Uninstall
if /i "%~1"=="/text" goto text
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0windows\ApolloSetup.ps1" -Uninstall
if not "%errorlevel%"=="99" exit /b %errorlevel%
:text
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File "%~dp0windows\Install-ApolloSchedule.ps1" -Uninstall
echo.
pause
