@echo off
setlocal enabledelayedexpansion

set SCRIPT_DIR=%~dp0
set ALL_RIDS=win-x64 win-arm64 linux-x64 linux-arm64 linux-musl-x64 linux-musl-arm64
set ALL_FRAMEWORKS=net8.0 net9.0 net10.0
set FRAMEWORK=
set ACTION=

:parse_args
if "%1"=="" goto :dispatch
if /i "%1"=="-f" set FRAMEWORK=%2& shift& shift& goto :parse_args
set ACTION=%1& shift& goto :parse_args

:dispatch
if not defined ACTION set ACTION=all
if /i "%ACTION%"=="all" goto :all
for %%r in (%ALL_RIDS%) do (
    if /i "%ACTION%"=="%%r" (
        if not defined FRAMEWORK set FRAMEWORK=net10.0
        set TF=!FRAMEWORK!
        call :publish_one %%r
        goto :end
    )
)
goto :usage

:all
if defined FRAMEWORK (
    set TF=!FRAMEWORK!
    for %%r in (%ALL_RIDS%) do call :publish_one %%r
) else (
    for %%f in (%ALL_FRAMEWORKS%) do (
        set TF=%%f
        for %%r in (%ALL_RIDS%) do call :publish_one %%r
    )
)
goto :end

:publish_one
echo ====== Publishing %1 / %TF% ======
dotnet publish "%SCRIPT_DIR%TestNupkg.csproj" -c Release -r %1 -f %TF% /nr:false
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
choice /t 1 /d y /n >nul
goto :eof

:usage
echo Usage: publish-aot-test.bat ^<target^> [-f ^<framework^>]
echo.
echo Targets:
echo   all (default)       Run all targets (all RIDs x all frameworks)
echo   win-x64             xwin + lld (Windows x64)
echo   win-arm64           xwin + lld (Windows ARM64)
echo   linux-x64           zig (Linux x64 glibc, dynamic CRT)
echo   linux-arm64         zig (Linux ARM64 glibc, dynamic CRT)
echo   linux-musl-x64      zig (Linux x64 musl, fully static)
echo   linux-musl-arm64    zig (Linux ARM64 musl, fully static)
echo.
echo Options:
echo   -f ^<framework^>    Target framework (default: net10.0)
echo                       Examples: -f net8.0, -f net9.0, -f net10.0
exit /b 1

:end
echo Done.
