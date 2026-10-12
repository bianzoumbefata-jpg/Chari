@echo off
title Synchronisation Chari Mobile
echo ===================================================
echo   Synchronisation du code vers Android et iOS
echo ===================================================
call npx cap sync
echo.
echo Synchronisation terminee avec succes !
pause
