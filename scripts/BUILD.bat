@echo off
setlocal
title ViperOS ISO Builder

echo.
echo ============================================
echo              ViperOS ISO Builder
echo ============================================
echo.

net session >nul 2>&1
if not %errorLevel%==0 (
    echo [INFO] Restarting as Administrator...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-wsl-and-build.ps1"
if not %errorLevel%==0 (
    echo.
    echo [FAIL] The ViperOS build failed. Review the output above.
    pause
    exit /b 1
)

echo.
echo [ OK ] ViperOS ISO build completed.
pause
