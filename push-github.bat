@echo off
set "GIT=C:\Program Files\Git\cmd\git.exe"

echo ========================================================
echo Synchronisation GitHub - Chari
echo ========================================================
echo.

echo [1/4] Verification du depot Git...
"%GIT%" init -b main

echo.
echo [2/4] Configuration du lien vers GitHub...
"%GIT%" branch -M main
"%GIT%" remote remove origin >nul 2>&1
"%GIT%" remote add origin https://github.com/bianzoumbefata-jpg/Chari.git

echo.
echo [3/4] Enregistrement des fichiers...
"%GIT%" add .
"%GIT%" commit -m "Chari: Application de rencontre au Tchad"

echo.
echo [4/4] Envoi vers GitHub...
echo Connexion en cours vers https://github.com/bianzoumbefata-jpg/Chari ...
"%GIT%" push -u origin main

echo.
echo ========================================================
if %ERRORLEVEL% EQU 0 (
    echo SUCCES : Tous vos fichiers sont en ligne sur GitHub !
    echo Lien : https://github.com/bianzoumbefata-jpg/Chari
) else (
    echo Verification requise. Verifiez la connexion GitHub.
)
echo ========================================================
echo.
pause
