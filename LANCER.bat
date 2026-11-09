@echo off
title Boost PC
cd /d "%~dp0"
net session >nul 2>&1
if %errorlevel% equ 0 goto lancer
echo Demande des droits administrateur...
echo (sans mot de passe administrateur, cliquez sur NON : le mode limite se lancera)
set "BOOSTPC_BAT=%~f0"
powershell -NoProfile -Command "try { Start-Process -FilePath $env:BOOSTPC_BAT -Verb RunAs -ErrorAction Stop; exit 0 } catch { exit 1 }"
if %errorlevel% equ 0 exit /b
:lancer
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0BoostPC.ps1"