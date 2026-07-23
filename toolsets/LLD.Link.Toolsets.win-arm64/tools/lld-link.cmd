@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0lld-link.ps1" %*
exit /b %ERRORLEVEL%