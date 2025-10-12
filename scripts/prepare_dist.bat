@echo off
REM Script to prepare distribution directory for Summit Hip Numbers on Windows

echo Preparing Summit Hip Numbers distribution...

REM Get the project root directory
set PROJECT_ROOT=%~dp0..
set DIST_DIR=%PROJECT_ROOT%\dist

REM Clean and create dist directory
if exist "%DIST_DIR%" rmdir /s /q "%DIST_DIR%"
mkdir "%DIST_DIR%"

REM Create subdirectories
mkdir "%DIST_DIR%\videos"
mkdir "%DIST_DIR%\splash"
mkdir "%DIST_DIR%\logo"

REM Copy the distribution config as the main config
copy "%PROJECT_ROOT%\config.dist.toml" "%DIST_DIR%\config.toml"

REM Copy assets
if exist "%PROJECT_ROOT%\assets\videos" (
    echo Copying video files...
    xcopy /s /i /q "%PROJECT_ROOT%\assets\videos\*" "%DIST_DIR%\videos\"
)

if exist "%PROJECT_ROOT%\assets\splash" (
    echo Copying splash images...
    xcopy /s /i /q "%PROJECT_ROOT%\assets\splash\*" "%DIST_DIR%\splash\"
)

if exist "%PROJECT_ROOT%\assets\logo" (
    echo Copying logo...
    xcopy /s /i /q "%PROJECT_ROOT%\assets\logo\*" "%DIST_DIR%\logo\"
)

REM Copy the release binary
if exist "%PROJECT_ROOT%\target\release\summit_hip_numbers.exe" (
    echo Copying Windows release binary...
    copy "%PROJECT_ROOT%\target\release\summit_hip_numbers.exe" "%DIST_DIR%\"
) else (
    echo Warning: Release binary not found. Run 'cargo build --release' first.
)

REM Copy required DLLs (GStreamer and other dependencies)
REM You may need to adjust these paths based on your GStreamer installation
if exist "C:\gstreamer\1.0\x86_64\bin\*.dll" (
    echo Copying GStreamer DLLs...
    xcopy /s /i /q "C:\gstreamer\1.0\x86_64\bin\*.dll" "%DIST_DIR%\"
)

REM Create a README for the distribution
(
echo Summit Hip Numbers Media Player
echo ===============================
echo.
echo To run the application:
echo - Double-click summit_hip_numbers.exe
echo.
echo Directory Structure:
echo - videos\    : Place your video files here ^(MP4 format recommended^)
echo - splash\    : Place splash screen images here ^(PNG, JPG, JPEG, BMP^)
echo - logo\      : Logo files
echo - config.toml: Configuration file ^(edit to customize behavior^)
echo.
echo Video Naming:
echo Name your videos with a 3-digit prefix for the hip number:
echo - 001_horse_name.mp4
echo - 002_another_horse.mp4
echo - etc.
echo.
echo Controls:
echo - Enter 3-digit hip number and press Enter to switch videos
echo - Up/Down arrows to navigate through videos
echo - ESC to exit ^(if not in kiosk mode^)
) > "%DIST_DIR%\README.txt"

echo Distribution prepared in: %DIST_DIR%
echo.
echo Directory structure:
dir /s "%DIST_DIR%"

pause