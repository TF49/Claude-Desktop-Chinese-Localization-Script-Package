@echo off
setlocal
cd /d %~dp0

echo Claude Desktop 汉化兼容入口：rollback.bat
echo 正在调用 PowerShell 版本的回滚流程...
echo.
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\rollback_localization.ps1"
set "EXITCODE=%errorlevel%"
echo.
pause
exit /b %EXITCODE%
