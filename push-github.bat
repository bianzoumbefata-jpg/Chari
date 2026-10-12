@echo off
chcp 65001 >nul
echo ========================================================
echo   Publication / Synchronisation automatique sur GitHub
echo ========================================================
set PATH=C:\Program Files\Git\cmd;%PATH%

git status >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo Initialisation du dépôt Git...
    git init -b main
)

echo.
echo Ajout des modifications...
git add .

echo.
echo Création du commit...
git commit -m "Mise à jour: %DATE% %TIME%"

echo.
echo Envoi vers GitHub (git push)...
git push -u origin main

echo.
if %ERRORLEVEL% EQU 0 (
    echo [SUCCÈS] Projet synchronisé avec GitHub !
) else (
    echo [INFO] Si vous n'avez pas encore lié votre dépôt, entrez l'URL GitHub:
    echo Exemple: git remote add origin https://github.com/votre-compte/votre-repo.git
)
pause
