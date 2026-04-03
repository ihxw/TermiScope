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
echo Setting up Tsinghua Mirrors for Dart and Flutter to resolve network issues...
set PUB_HOSTED_URL=https://mirrors.tuna.tsinghua.edu.cn/dart-pub
set FLUTTER_STORAGE_BASE_URL=https://mirrors.tuna.tsinghua.edu.cn/flutter

echo.
echo Cleaning Flutter project...
call flutter clean

echo.
echo Getting Flutter dependencies...
call flutter pub get

echo.
echo Building Windows application...
call flutter build windows --debug

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
