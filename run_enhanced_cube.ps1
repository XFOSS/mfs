# Enhanced Spinning Cube Demo - PowerShell Build Script
# This script builds and runs the enhanced textured spinning cube with 3D grid

Write-Host "=== MFS Enhanced Spinning Cube with Grid ===" -ForegroundColor Cyan
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

# Build the enhanced spinning cube application
Write-Host "Building enhanced spinning cube with grid..." -ForegroundColor Yellow
Write-Host "Build configuration: ReleaseFast with OpenGL optimization" -ForegroundColor Gray

try {
    & zig build --build-file build_simple_cube.zig -Doptimize=ReleaseFast
    
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
$exePath = "zig-out\bin\simple_cube.exe"
if (-not (Test-Path $exePath)) {
    Write-Host "Error: simple_cube.exe not found at $exePath" -ForegroundColor Red
    Write-Host "Build may have failed silently" -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

# Display enhanced application info
Write-Host "=== Enhanced Spinning Cube Demo Ready ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "✨ NEW FEATURES:" -ForegroundColor White
Write-Host "  🎯 3D Grid Background - Interactive spatial reference" -ForegroundColor Green
Write-Host "  🌈 Gradient Cube Faces - Enhanced color transitions" -ForegroundColor Green
Write-Host "  📐 Axis Indicators - Red(X), Green(Y), Blue(Z) reference lines" -ForegroundColor Green
Write-Host "  💫 Transparency Effects - Semi-transparent grid with depth" -ForegroundColor Green
Write-Host "  🔄 Smooth Animation - Dual-axis rotation with perfect timing" -ForegroundColor Green
Write-Host ""
Write-Host "Technical Specifications:" -ForegroundColor White
Write-Host "  • Resolution: 800x600 optimized for grid visibility" -ForegroundColor Gray
Write-Host "  • Rendering: OpenGL with depth testing and alpha blending" -ForegroundColor Gray
Write-Host "  • Grid: 21x21 lines with 10-unit spacing" -ForegroundColor Gray
Write-Host "  • Frame Rate: 60 FPS with 16ms sleep precision" -ForegroundColor Gray
Write-Host "  • Color Space: RGB with gradient interpolation" -ForegroundColor Gray
Write-Host ""
Write-Host "Controls & Navigation:" -ForegroundColor White
Write-Host "  • ESC key: Exit application" -ForegroundColor Gray
Write-Host "  • Window Close: Exit application" -ForegroundColor Gray
Write-Host "  • Window: Resizable for different viewing angles" -ForegroundColor Gray
Write-Host ""
Write-Host "Visual Elements:" -ForegroundColor White
Write-Host "  • Cube rotates: 50°/sec on X-axis, 80°/sec on Y-axis" -ForegroundColor Gray
Write-Host "  • Grid color: Semi-transparent blue-gray (alpha 0.6)" -ForegroundColor Gray
Write-Host "  • Background: Deep space blue (0.05, 0.05, 0.15)" -ForegroundColor Gray
Write-Host "  • Faces: Red, Green, Blue, Yellow, Magenta, Cyan" -ForegroundColor Gray
Write-Host ""

# Ask user if they want to run
$response = Read-Host "Launch the enhanced cube demo? (Y/n)"
if ($response -eq "" -or $response -eq "Y" -or $response -eq "y") {
    Write-Host ""
    Write-Host "🚀 Starting Enhanced Spinning Cube Demo..." -ForegroundColor Cyan
    Write-Host "Watch the beautiful 3D grid interact with the rotating cube!" -ForegroundColor Green
    Write-Host "The grid provides spatial context and depth perception." -ForegroundColor Gray
    Write-Host ""
    
    # Run the application
    try {
        & ".\$exePath"
        Write-Host ""
        Write-Host "✅ Demo finished successfully!" -ForegroundColor Green
        Write-Host "Thank you for experiencing the enhanced cube with grid!" -ForegroundColor Cyan
    } catch {
        Write-Host ""
        Write-Host "❌ Demo encountered an error: $_" -ForegroundColor Red
        Write-Host "This might be due to OpenGL driver compatibility." -ForegroundColor Yellow
        Write-Host "Try updating your graphics drivers." -ForegroundColor Gray
    }
} else {
    Write-Host ""
    Write-Host "📁 Demo build complete." -ForegroundColor Yellow
    Write-Host "Run '$exePath' manually when ready." -ForegroundColor Gray
    Write-Host "Enjoy the enhanced 3D experience!" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "=== Enhanced Demo Session Complete ===" -ForegroundColor Cyan
Write-Host "Grid + Cube = Perfect 3D Visualization! 🎮✨" -ForegroundColor Magenta
Read-Host "Press Enter to exit"