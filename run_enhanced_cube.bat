@echo off
echo ========================================
echo  Enhanced Spinning Cube with 3D Grid
echo ========================================
echo.

REM Check if Zig is available
zig version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Zig compiler not found in PATH
    echo Please install Zig from https://ziglang.org/download/
    echo and ensure it's added to your system PATH
    echo.
    pause
    exit /b 1
)

echo [INFO] Zig compiler detected
echo.

REM Clean previous builds
echo [INFO] Cleaning previous builds...
if exist "zig-out" rmdir /s /q "zig-out" 2>nul
if exist "zig-cache" rmdir /s /q "zig-cache" 2>nul
if exist ".zig-cache" rmdir /s /q ".zig-cache" 2>nul
echo [INFO] Build cache cleared
echo.

REM Build the enhanced spinning cube
echo [INFO] Building enhanced spinning cube with 3D grid...
echo [INFO] Configuration: ReleaseFast with OpenGL optimization
zig build --build-file build_simple_cube.zig -Doptimize=ReleaseFast

if errorlevel 1 (
    echo.
    echo [ERROR] Build failed! Check error messages above.
    echo Common issues:
    echo   - Missing system libraries
    echo   - Zig version compatibility
    echo   - Source code syntax errors
    echo.
    pause
    exit /b 1
)

echo.
echo [SUCCESS] Build completed successfully!
echo.

REM Verify executable exists
if not exist "zig-out\bin\simple_cube.exe" (
    echo [ERROR] Executable not found: zig-out\bin\simple_cube.exe
    echo Build may have completed but output file is missing
    echo.
    pause
    exit /b 1
)

REM Display feature information
echo ========================================
echo         ENHANCED FEATURES
echo ========================================
echo.
echo  3D Grid Background:
echo    * 21x21 grid lines with 1-unit spacing
echo    * Semi-transparent blue-gray appearance
echo    * Provides spatial reference and depth
echo.
echo  Gradient Cube:
echo    * 6 colorful faces with smooth transitions
echo    * Dual-axis rotation (50deg/s X, 80deg/s Y)
echo    * Real-time animation at 60 FPS
echo.
echo  Axis Indicators:
echo    * Red line = X-axis (-15 to +15 units)
echo    * Green line = Y-axis (-15 to +15 units)
echo    * Blue line = Z-axis (-15 to +15 units)
echo.
echo  Rendering:
echo    * OpenGL with depth testing and alpha blending
echo    * Hardware-accelerated 3D graphics
echo    * Native Windows window (800x600)
echo.
echo ========================================
echo           CONTROLS
echo ========================================
echo.
echo  ESC Key .......... Exit application
echo  Close Window ..... Exit application
echo  Window Resize .... Adjust viewport
echo.

REM Prompt to run
set /p response="Start the enhanced cube demo? (Y/n): "
if /i "%response%"=="n" (
    echo.
    echo [INFO] Demo ready to run manually:
    echo       zig-out\bin\simple_cube.exe
    echo.
    pause
    exit /b 0
)

echo.
echo ========================================
echo      LAUNCHING ENHANCED DEMO
echo ========================================
echo.
echo [INFO] Starting enhanced spinning cube with 3D grid...
echo [INFO] Watch the beautiful interaction between cube and grid!
echo [INFO] Grid provides spatial context and depth perception
echo.

REM Run the enhanced application
cd /d "%~dp0"
"zig-out\bin\simple_cube.exe"

REM Check exit status
if errorlevel 1 (
    echo.
    echo [WARNING] Application exited with error code %errorlevel%
    echo This might be due to:
    echo   - OpenGL driver compatibility issues
    echo   - Graphics hardware limitations
    echo   - Display configuration problems
    echo.
    echo Suggestions:
    echo   - Update graphics drivers
    echo   - Check OpenGL support
    echo   - Try running as administrator
    echo.
) else (
    echo.
    echo [SUCCESS] Enhanced cube demo completed successfully!
    echo Thank you for experiencing the 3D grid visualization!
)

echo.
echo ========================================
echo       DEMO SESSION COMPLETE
echo ========================================
echo  Grid + Cube = Perfect 3D Visualization!
echo ========================================
echo.
pause