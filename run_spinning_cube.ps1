# Spinning Cube Demo - PowerShell Build Script
# This script builds and runs the textured spinning cube application

Write-Host "=== MFS Spinning Cube Demo Builder ===" -ForegroundColor Cyan
Write-Host ""

# Check if Zig is available
try {
    $zigVersion = zig version 2>$null
    Write-Host "Zig compiler found: $zigVersion" -ForegroundColor Green
} catch {
    Write-Host "Error: Zig compiler not found in PATH" -ForegroundColor Red
    Write-Host "Please install Zig and ensure it's in your PATH" -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host ""

# Clean previous builds
Write-Host "Cleaning previous builds..." -ForegroundColor Yellow
if (Test-Path "zig-out") { Remove-Item -Recurse -Force "zig-out" }
if (Test-Path "zig-cache") { Remove-Item -Recurse -Force "zig-cache" }
if (Test-Path ".zig-cache") { Remove-Item -Recurse -Force ".zig-cache" }

Write-Host "Previous builds cleaned" -ForegroundColor Green
Write-Host ""

# Build the spinning cube application
Write-Host "Building spinning cube application..." -ForegroundColor Yellow
Write-Host "Build configuration: ReleaseFast" -ForegroundColor Gray

try {
    & zig build --build-file build_spinning_cube.zig -Doptimize=ReleaseFast
    
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed with exit code $LASTEXITCODE"
    }
    
    Write-Host ""
    Write-Host "Build successful!" -ForegroundColor Green
} catch {
    Write-Host ""
    Write-Host "Build failed! Error: $_" -ForegroundColor Red
    Write-Host "Check the error messages above for details." -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host ""

# Check if executable exists
$exePath = "zig-out\bin\spinning_cube.exe"
if (-not (Test-Path $exePath)) {
    Write-Host "Error: spinning_cube.exe not found at $exePath" -ForegroundColor Red
    Write-Host "Build may have failed silently" -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

# Display application info
Write-Host "=== Spinning Cube Demo Ready ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Features:" -ForegroundColor White
Write-Host "  ✓ Textured spinning cube with procedural checkered pattern" -ForegroundColor Green
Write-Host "  ✓ PBR material system with metallic and roughness properties" -ForegroundColor Green
Write-Host "  ✓ Dynamic lighting with orbiting light source" -ForegroundColor Green
Write-Host "  ✓ Real-time vertex and fragment shaders" -ForegroundColor Green
Write-Host "  ✓ Cross-platform graphics backend support" -ForegroundColor Green
Write-Host ""
Write-Host "Controls:" -ForegroundColor White
Write-Host "  • ESC key or close window to exit" -ForegroundColor Gray
Write-Host "  • Window is resizable" -ForegroundColor Gray
Write-Host ""
Write-Host "Technical Details:" -ForegroundColor White
Write-Host "  • Resolution: 1280x720" -ForegroundColor Gray
Write-Host "  • Target FPS: ~60" -ForegroundColor Gray
Write-Host "  • Graphics API: Auto-detected (Vulkan/DirectX/OpenGL)" -ForegroundColor Gray
Write-Host ""

# Ask user if they want to run
$response = Read-Host "Start the demo? (Y/n)"
if ($response -eq "" -or $response -eq "Y" -or $response -eq "y") {
    Write-Host ""
    Write-Host "Starting Spinning Cube Demo..." -ForegroundColor Cyan
    Write-Host "Watch for console output with FPS and runtime statistics" -ForegroundColor Gray
    Write-Host ""
    
    # Run the application
    try {
        & ".\$exePath"
        Write-Host ""
        Write-Host "Demo finished successfully!" -ForegroundColor Green
    } catch {
        Write-Host ""
        Write-Host "Demo encountered an error: $_" -ForegroundColor Red
    }
} else {
    Write-Host ""
    Write-Host "Demo build complete. Run '$exePath' manually when ready." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Demo Session Complete ===" -ForegroundColor Cyan
Read-Host "Press Enter to exit"