@echo off
setlocal
cd /d %~dp0

net session >nul 2>&1
if errorlevel 1 (
    echo ========================================
    echo Administrator privileges are required.
    echo Requesting elevation...
    echo If no UAC prompt appears, check whether another window is covering it.
    echo Cancelling the prompt will stop this window without applying the patch.
    echo ========================================
    powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "try { Start-Process -FilePath '%~f0' -Verb RunAs -ErrorAction Stop; exit 0 } catch { exit 1 }"
    if errorlevel 1 (
        echo.
        echo Failed to start an elevated window.
        echo Right-click this file and choose Run as administrator, then try again.
        echo.
        pause
        exit /b 1
    )
    echo.
    echo An elevated window launch was requested.
    echo If no new window appears, run this file as administrator manually.
    echo.
    pause
    exit /b 0
)

echo ========================================
echo Claude Desktop localization apply
echo Includes: backup ^> apply ^> verify
echo ========================================
echo.
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\apply_localization.ps1"
set "EXITCODE=%errorlevel%"
echo.
if not "%EXITCODE%"=="0" (
    echo Apply failed. Exit code: %EXITCODE%
    echo Keep this window open so the error output can be reviewed.
    echo.
)
pause
exit /b %EXITCODE%
