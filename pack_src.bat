@echo off
setlocal

dotnet pack "%~dp0src\PublishAotCross.Tools.nuproj" -o "%~dp0artifacts" --force
if %ERRORLEVEL% neq 0 (
  echo Pack failed with exit code %ERRORLEVEL%
  exit /b %ERRORLEVEL%
)

echo Package created in artifacts folder.
