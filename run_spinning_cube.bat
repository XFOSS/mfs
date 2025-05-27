@echo off
echo Building and running Spinning Cube Demo...
echo.

REM Check if Zig is available
zig version >nul 2>&1
if errorlevel 1 (
    echo Error: Zig compiler not found in PATH
    echo Please install Zig and ensure it's in your PATH
    pause
    exit /b 1
)

echo Zig compiler found
echo.

REM Clean previous builds
if exist "zig-out" rmdir /s /q "zig-out"
if exist "zig-cache" rmdir /s /q "zig-cache"

echo Cleaned previous builds
echo.

REM Build the spinning cube application
echo Building spinning cube application...
zig build --build-file build_spinning_cube.zig -Doptimize=ReleaseFast

if errorlevel 1 (
    echo.
    echo Build failed! Check the error messages above.
    pause
    exit /b 1
)

echo.
echo Build successful!
echo.

REM Check if executable exists
if not exist "zig-out\bin\spinning_cube.exe" (
    echo Error: spinning_cube.exe not found in zig-out\bin\
    echo Build may have failed silently
    pause
    exit /b 1
)

echo Starting Spinning Cube Demo...
echo Controls: 
echo   - ESC or close window to exit
echo   - Watch the textured cube spin with dynamic lighting
echo.

REM Run the application
cd /d "%~dp0"
"zig-out\bin\spinning_cube.exe"

echo.
echo Demo finished.
pause