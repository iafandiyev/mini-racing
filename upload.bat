
@echo off
title Mini Racing - GitHub Upload
color 0A

echo ========================================
echo       MINI RACING GITHUB UPLOAD
echo ========================================
echo.

git --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Git is not installed!
    pause
    exit /b 1
)

if not exist ".git" (
    echo Initializing Git...
    git init
)

git branch -M main

echo.
echo Adding project files...
git add .

echo.
set /p COMMIT_MSG=Enter commit message (or press Enter): 
if "%COMMIT_MSG%"=="" set COMMIT_MSG=Update Mini Racing

git commit -m "%COMMIT_MSG%"

if errorlevel 1 (
    echo No changes to commit, or commit failed.
)

echo.
echo Connecting GitHub repository...
git remote get-url origin >nul 2>&1

if errorlevel 1 (
    git remote add origin https://github.com/iafandiyev/mini-racing.git
) else (
    git remote set-url origin https://github.com/iafandiyev/mini-racing.git
)

echo.
echo Uploading to GitHub...
git push -u origin main

if errorlevel 1 (
    echo.
    echo UPLOAD FAILED!
    echo Check your GitHub login and repository permissions.
    pause
    exit /b 1
)

echo.
echo ========================================
echo          UPLOAD SUCCESSFUL!
echo ========================================
echo.
echo Repository:
echo https://github.com/iafandiyev/mini-racing
echo.
echo Open Actions to download your IPA:
echo https://github.com/iafandiyev/mini-racing/actions
echo.

pause
