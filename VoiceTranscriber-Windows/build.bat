@echo off
setlocal

set VERSION=1.0.0
set CONFIG=%1
if "%CONFIG%"=="" set CONFIG=Release

echo ===================================
echo  Building Verbalize v%VERSION%
echo  Configuration: %CONFIG%
echo ===================================

:: Restore NuGet packages
echo.
echo [1/3] Restoring packages...
dotnet restore Verbalize\Verbalize.csproj
if errorlevel 1 (
    echo ERROR: Package restore failed.
    exit /b 1
)

:: Build
echo.
echo [2/3] Building...
dotnet build Verbalize\Verbalize.csproj -c %CONFIG% --no-restore
if errorlevel 1 (
    echo ERROR: Build failed.
    exit /b 1
)

:: Publish (self-contained for easy distribution)
if "%2"=="--publish" (
    echo.
    echo [3/3] Publishing self-contained...
    dotnet publish Verbalize\Verbalize.csproj -c %CONFIG% -r win-x64 --self-contained true -o publish\Verbalize
    if errorlevel 1 (
        echo ERROR: Publish failed.
        exit /b 1
    )
    echo.
    echo Published to: publish\Verbalize\
) else (
    echo.
    echo [3/3] Skipping publish (use --publish flag to create distributable)
)

echo.
echo ===================================
echo  Build complete!
echo ===================================
echo.
echo To run: dotnet run --project Verbalize\Verbalize.csproj -c %CONFIG%
echo To publish: build.bat Release --publish
