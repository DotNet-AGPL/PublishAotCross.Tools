@echo off
setlocal enabledelayedexpansion

set CONFIG=Release

if "%1"=="" goto :all
if "%1"=="all" goto :all
if "%1"=="lld" goto :lld
if "%1"=="lld-linux-x64" goto :lld_linux_x64
if "%1"=="lld-linux-arm64" goto :lld_linux_arm64
if "%1"=="lld-win-arm64" goto :lld_win_arm64
if "%1"=="lld-osx-arm64" goto :lld_osx_arm64
if "%1"=="store-x64" goto :store_x64
if "%1"=="store-arm64" goto :store_arm64
goto :usage

:all
call :store_x64
call :store_arm64
call :lld
call :lld_linux_x64
call :lld_linux_arm64
call :lld_win_arm64
call :lld_osx_arm64
goto :end

:store_x64
echo Packing XWin.Store.x64...
dotnet pack "%~dp0toolsets\XWin.Store.x64" -o "%~dp0artifacts" --force
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
goto :end

:store_arm64
echo Packing XWin.Store.arm64...
dotnet pack "%~dp0toolsets\XWin.Store.arm64" -o "%~dp0artifacts" --force
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
goto :end

:lld
echo Packing LLD.Link.Toolsets.win-x64...
dotnet pack "%~dp0toolsets\LLD.Link.Toolsets.win-x64" -o "%~dp0artifacts" --force
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
goto :end

:lld_linux_x64
echo Packing LLD.Link.Toolsets.linux-x64...
dotnet pack "%~dp0toolsets\LLD.Link.Toolsets.linux-x64" -o "%~dp0artifacts" --force
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
goto :end

:lld_linux_arm64
echo Packing LLD.Link.Toolsets.linux-arm64...
dotnet pack "%~dp0toolsets\LLD.Link.Toolsets.linux-arm64" -o "%~dp0artifacts" --force
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
goto :end

:lld_win_arm64
echo Packing LLD.Link.Toolsets.win-arm64...
dotnet pack "%~dp0toolsets\LLD.Link.Toolsets.win-arm64" -o "%~dp0artifacts" --force
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
goto :end

:lld_osx_arm64
echo Packing LLD.Link.Toolsets.osx-arm64...
dotnet pack "%~dp0toolsets\LLD.Link.Toolsets.osx-arm64" -o "%~dp0artifacts" --force
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
goto :end

:usage
echo Usage: pack_toolsets.bat ^<target^>
echo.
echo Targets:
echo   all (default)     Pack all packages in dependency order
echo   store-x64         Pack XWin.Store.x64
echo   store-arm64       Pack XWin.Store.arm64
echo   lld               Pack LLD.Link.Toolsets.win-x64
echo   lld-linux-x64     Pack LLD.Link.Toolsets.linux-x64
echo   lld-linux-arm64   Pack LLD.Link.Toolsets.linux-arm64
echo   lld-win-arm64     Pack LLD.Link.Toolsets.win-arm64
echo   lld-osx-arm64     Pack LLD.Link.Toolsets.osx-arm64
exit /b 1

:end
echo Done.
