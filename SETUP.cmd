@echo off
setlocal
cd /d "%~dp0"

echo ============================================================
echo              WikiArabicTools Setup Launcher
echo ============================================================
echo.
echo Starting SETUP.ps1 with a temporary Process-scoped Bypass.
echo Your Windows execution policy is NOT changed.
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0SETUP.ps1" %*
set "EXITCODE=%ERRORLEVEL%"

echo.
if not "%EXITCODE%"=="0" (
    echo Setup exited with code %EXITCODE%.
) else (
    echo Setup completed successfully.
)
echo.
pause
exit /b %EXITCODE%
