@echo off
rem Houston - double-click to set up this PC: connect to Houston on your Apollo and pick shortcuts.
rem Opens the setup window (windows\ApolloSetup.ps1). If the window can't be shown,
rem or you run "Setup.bat /text", the same setup runs as questions in this window.
rem "-ExecutionPolicy Bypass" applies to this one run only; no system setting is changed.
setlocal
title Houston - Setup
if not exist "%~dp0windows\ApolloSetup.ps1" (
  echo Can't find the windows folder next to this file.
  echo Unzip the whole folder first, then run Setup.bat from inside it.
  pause
  exit /b 1
)
if /i "%~1"=="/text" goto text
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0windows\ApolloSetup.ps1"
if not "%errorlevel%"=="99" exit /b %errorlevel%
:text
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File "%~dp0windows\Install-ApolloSchedule.ps1"
echo.
if errorlevel 1 (echo Setup did not finish. See the message above.) else (echo All done. You can close this window.)
pause
