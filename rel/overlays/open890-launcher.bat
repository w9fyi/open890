@echo off
setlocal
cd /d "%~dp0"

set "OPEN890_URL=http://localhost:4000"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0open890-launcher.ps1" -RootDir "%~dp0" -Url "%OPEN890_URL%" -TimeoutSeconds 45
exit /b %ERRORLEVEL%
