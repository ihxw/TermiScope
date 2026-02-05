@echo off
REM Find Visual Studio installation path
for /f "usebackq tokens=*" %%i in (`"C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe" -latest -property installationPath`) do (
    set VS_PATH=%%i
)

if "%VS_PATH%"=="" (
    echo Error: Could not find Visual Studio installation
    exit /b 1
)

echo Found Visual Studio at: %VS_PATH%
echo.
echo Loading Visual Studio Developer Environment...
call "%VS_PATH%\Common7\Tools\VsDevCmd.bat"

echo.
echo Cleaning Flutter project...
flutter clean

echo.
echo Getting Flutter dependencies...
flutter pub get

echo.
echo Building Windows application...
flutter build windows --debug

echo.
if %ERRORLEVEL% EQU 0 (
    echo ========================================
    echo Build completed successfully!
    echo ========================================
) else (
    echo ========================================
    echo Build failed with error code: %ERRORLEVEL%
    echo ========================================
)

pause
