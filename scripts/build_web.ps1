#!/usr/bin/env pwsh
<#
.SYNOPSIS
    MFS Engine Web Build Script for Windows

.DESCRIPTION
    This PowerShell script builds the MFS Engine for WebAssembly and sets up a local development server.

.PARAMETER Optimize
    Build optimization level (Debug, ReleaseSafe, ReleaseFast, ReleaseSmall)

.PARAMETER Clean
    Clean build artifacts before building

.PARAMETER NoServer
    Don't start the development server after building

.PARAMETER NoBrowser
    Don't automatically open the browser

.PARAMETER Port
    Port for the development server (default: 8080)

.PARAMETER Deploy
    Create a deployment package

.EXAMPLE
    .\build_web.ps1 -Optimize ReleaseFast -Clean
#>

param(
    [ValidateSet("Debug", "ReleaseSafe", "ReleaseFast", "ReleaseSmall")]
    [string]$Optimize = "Debug",
    
    [switch]$Clean,
    [switch]$NoServer,
    [switch]$NoBrowser,
    [int]$Port = 8080,
    [switch]$Deploy,
    [string[]]$BuildArgs = @()
)

# Configuration
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$WebOutputDir = Join-Path $ProjectRoot "zig-out\web"
$WebTemplateDir = Join-Path $ProjectRoot "web"

# Colors for output
$ErrorColor = "Red"
$SuccessColor = "Green"
$InfoColor = "Cyan"
$WarningColor = "Yellow"

function Write-Info {
    param([string]$Message)
    Write-Host $Message -ForegroundColor $InfoColor
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor $SuccessColor
}

function Write-Error {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor $ErrorColor
}

function Write-Warning {
    param([string]$Message)
    Write-Host "⚠ $Message" -ForegroundColor $WarningColor
}

function Test-Command {
    param([string]$Command)
    
    try {
        $null = Get-Command $Command -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Invoke-BuildCommand {
    param(
        [string[]]$Command,
        [string]$WorkingDirectory = $ProjectRoot
    )
    
    Write-Info "Running: $($Command -join ' ')"
    
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $Command[0]
    $startInfo.Arguments = ($Command[1..($Command.Length-1)] -join ' ')
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    
    try {
        $process.Start() | Out-Null
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        
        if ($stdout) {
            Write-Host $stdout
        }
        
        if ($process.ExitCode -ne 0) {
            if ($stderr) {
                Write-Error $stderr
            }
            throw "Command failed with exit code $($process.ExitCode)"
        }
        
        return $process.ExitCode
    }
    finally {
        $process.Dispose()
    }
}

function Test-Dependencies {
    Write-Info "Checking dependencies..."
    
    # Check Zig
    if (Test-Command "zig") {
        try {
            $zigVersion = & zig version 2>$null
            Write-Success "Zig version: $zigVersion"
        }
        catch {
            Write-Error "Zig found but version check failed"
            exit 1
        }
    }
    else {
        Write-Error "Zig not found. Please install Zig 0.15.0 or later."
        Write-Info "Download from: https://ziglang.org/download/"
        exit 1
    }
    
    # Check Emscripten (optional)
    if (Test-Command "emcc") {
        Write-Success "Emscripten found"
    }
    else {
        Write-Warning "Emscripten not found. Some features may be limited."
        Write-Info "Install from: https://emscripten.org/docs/getting_started/downloads.html"
    }
    
    Write-Info "Dependencies check completed.`n"
}

function Clear-BuildArtifacts {
    Write-Info "Cleaning previous build..."
    
    if (Test-Path $WebOutputDir) {
        Remove-Item $WebOutputDir -Recurse -Force
        Write-Info "Removed $WebOutputDir"
    }
    
    $zigCache = Join-Path $ProjectRoot ".zig-cache"
    if (Test-Path $zigCache) {
        Remove-Item $zigCache -Recurse -Force
        Write-Info "Removed .zig-cache"
    }
    
    Write-Info "Clean completed.`n"
}

function Build-ForWeb {
    Write-Info "Building MFS Engine for Web (optimization: $Optimize)..."
    
    $buildCommand = @(
        "zig", "build", "web",
        "-Doptimize=$Optimize",
        "-Dwebgpu=true",
        "-Dopengles=true",
        "-Dvulkan=false",
        "-Dd3d11=false",
        "-Dd3d12=false",
        "-Dmetal=false"
    )
    
    if ($BuildArgs) {
        $buildCommand += $BuildArgs
    }
    
    try {
        Invoke-BuildCommand $buildCommand
        Write-Success "Build completed successfully.`n"
    }
    catch {
        Write-Error "Build failed. Check the error messages above."
        exit 1
    }
}

function Setup-WebFiles {
    Write-Info "Setting up web files..."
    
    # Ensure output directory exists
    if (!(Test-Path $WebOutputDir)) {
        New-Item -ItemType Directory -Path $WebOutputDir -Force | Out-Null
    }
    
    # Copy HTML template if it exists
    $htmlTemplate = Join-Path $WebTemplateDir "index.html"
    if (Test-Path $htmlTemplate) {
        Copy-Item $htmlTemplate (Join-Path $WebOutputDir "index.html") -Force
        Write-Info "Copied index.html"
    }
    else {
        # Create basic HTML file
        New-BasicHtml
    }
    
    # Copy other web assets
    $assetFiles = @("style.css", "favicon.ico", "manifest.json")
    foreach ($assetFile in $assetFiles) {
        $assetPath = Join-Path $WebTemplateDir $assetFile
        if (Test-Path $assetPath) {
            Copy-Item $assetPath (Join-Path $WebOutputDir $assetFile) -Force
            Write-Info "Copied $assetFile"
        }
    }
    
    Write-Info "Web files setup completed.`n"
}

function New-BasicHtml {
    $htmlContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MFS Engine - WebAssembly</title>
    <style>
        body { margin: 0; padding: 20px; background: #1a1a1a; color: white; font-family: sans-serif; }
        canvas { border: 1px solid #333; display: block; margin: 20px auto; }
        .info { text-align: center; margin: 20px; }
        .controls { text-align: center; margin: 20px; }
        button { padding: 10px 20px; margin: 5px; background: #4a9eff; color: white; border: none; border-radius: 5px; cursor: pointer; }
        button:hover { background: #357abd; }
    </style>
</head>
<body>
    <div class="info">
        <h1>MFS Engine - WebAssembly Demo</h1>
        <p>DirectX 12 + WebGPU Multi-Platform Graphics Engine</p>
        <p id="status">Loading...</p>
    </div>
    <canvas id="canvas" width="800" height="600"></canvas>
    <div class="controls">
        <button onclick="if(Module._web_init) Module._web_init(800, 600)">Start Engine</button>
        <button onclick="toggleFullscreen()">Fullscreen</button>
    </div>
    <script>
        var Module = {
            canvas: document.getElementById('canvas'),
            print: function(text) { 
                console.log('Engine:', text);
                document.getElementById('status').textContent = text;
            },
            printErr: function(text) { 
                console.error('Engine Error:', text);
                document.getElementById('status').textContent = 'Error: ' + text;
            },
            onRuntimeInitialized: function() {
                document.getElementById('status').textContent = 'Engine Ready';
            }
        };
        
        function toggleFullscreen() {
            if (document.fullscreenElement) {
                document.exitFullscreen();
            } else {
                document.getElementById('canvas').requestFullscreen();
            }
        }
    </script>
    <script src="mfs-web.js"></script>
</body>
</html>
"@
    
    $htmlPath = Join-Path $WebOutputDir "index.html"
    Set-Content -Path $htmlPath -Value $htmlContent -Encoding UTF8
    Write-Info "Created basic HTML file"
}

function Test-BuildOutput {
    Write-Info "Verifying build output..."
    
    $requiredFiles = @("mfs-web.wasm", "mfs-web.js")
    $missingFiles = @()
    
    foreach ($fileName in $requiredFiles) {
        $filePath = Join-Path $WebOutputDir $fileName
        if (Test-Path $filePath) {
            $fileSize = (Get-Item $filePath).Length
            Write-Success "$fileName ($($fileSize.ToString('N0')) bytes)"
        }
        else {
            $missingFiles += $fileName
            Write-Error "$fileName - Missing"
        }
    }
    
    if ($missingFiles.Count -gt 0) {
        Write-Error "Missing required files: $($missingFiles -join ', ')"
        exit 1
    }
    
    Write-Info "Build verification completed.`n"
}

function Start-DevServer {
    if ($NoServer) {
        Write-Info "Skipping development server as requested."
        Write-Info "To test manually, run: python -m http.server $Port"
        Write-Info "Or use: npx serve $WebOutputDir -p $Port"
        return
    }
    
    Write-Info "Starting development server on port $Port..."
    
    # Try different server options
    $serverStarted = $false
    
    # Try Python
    if ((Test-Command "python") -and !$serverStarted) {
        try {
            Set-Location $WebOutputDir
            $serverUrl = "http://localhost:$Port"
            Write-Success "Server running at $serverUrl"
            Write-Info "Press Ctrl+C to stop the server"
            
            if (!$NoBrowser) {
                Start-Sleep -Seconds 1
                Start-Process $serverUrl
            }
            
            & python -m http.server $Port --bind 127.0.0.1
            $serverStarted = $true
        }
        catch {
            Write-Warning "Python server failed: $_"
        }
        finally {
            Set-Location $ProjectRoot
        }
    }
    
    # Try Node.js serve package
    if ((Test-Command "npx") -and !$serverStarted) {
        try {
            $serverUrl = "http://localhost:$Port"
            Write-Success "Server running at $serverUrl"
            Write-Info "Press Ctrl+C to stop the server"
            
            if (!$NoBrowser) {
                Start-Sleep -Seconds 1
                Start-Process $serverUrl
            }
            
            & npx serve $WebOutputDir -p $Port -s
            $serverStarted = $true
        }
        catch {
            Write-Warning "Node.js serve failed: $_"
        }
    }
    
    # Try PowerShell simple server (Windows 10/11)
    if (!$serverStarted) {
        Write-Warning "No suitable web server found."
        Write-Info "Please install Python or Node.js to use the built-in server."
        Write-Info "Alternatively, use any web server to serve files from: $WebOutputDir"
    }
}

function New-DeploymentPackage {
    Write-Info "Creating deployment package..."
    
    $packageDir = Join-Path $ProjectRoot "deploy"
    if (Test-Path $packageDir) {
        Remove-Item $packageDir -Recurse -Force
    }
    
    Copy-Item $WebOutputDir $packageDir -Recurse
    
    # Create deployment info
    $deployInfo = @{
        engine = "MFS Engine"
        version = "1.0.0"
        build_time = Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC"
        platform = "WebAssembly"
        optimization = $Optimize
        files = (Get-ChildItem $packageDir -File).Name
        deployment_notes = @{
            requirements = @(
                "HTTPS required for WebGPU",
                "Modern browser with WebAssembly support",
                "Proper MIME type for .wasm files (application/wasm)"
            )
            headers = @{
                "Cross-Origin-Embedder-Policy" = "require-corp"
                "Cross-Origin-Opener-Policy" = "same-origin"
            }
            server_config = @{
                nginx = "location ~* \.wasm$ { add_header Content-Type application/wasm; }"
                apache = "AddType application/wasm .wasm"
                iis = "<mimeMap fileExtension='.wasm' mimeType='application/wasm' />"
            }
        }
    }
    
    $deployInfoPath = Join-Path $packageDir "deploy-info.json"
    $deployInfo | ConvertTo-Json -Depth 4 | Set-Content $deployInfoPath -Encoding UTF8
    
    Write-Success "Deployment package created in $packageDir"
    
    # Create a simple deployment script
    $deployScript = @"
@echo off
echo MFS Engine Web Deployment
echo ========================
echo.
echo This package contains the MFS Engine compiled for WebAssembly.
echo.
echo Requirements:
echo - HTTPS server (required for WebGPU)
echo - Proper MIME type for .wasm files
echo - Modern browser with WebAssembly support
echo.
echo To deploy:
echo 1. Upload all files to your web server
echo 2. Ensure .wasm files are served with Content-Type: application/wasm
echo 3. Set CORS headers if needed (see deploy-info.json)
echo 4. Access via HTTPS
echo.
pause
"@
    
    Set-Content (Join-Path $packageDir "deploy.bat") $deployScript -Encoding UTF8
}

# Main execution
try {
    Write-Host "MFS Engine Web Build Script" -ForegroundColor Magenta
    Write-Host "================================" -ForegroundColor Magenta
    Write-Host ""
    
    # Check dependencies
    Test-Dependencies
    
    # Clean if requested
    if ($Clean) {
        Clear-BuildArtifacts
    }
    
    # Build for web
    Build-ForWeb
    
    # Setup web files
    Setup-WebFiles
    
    # Verify build
    Test-BuildOutput
    
    # Create deployment package if requested
    if ($Deploy) {
        New-DeploymentPackage
    }
    
    Write-Success "Web build completed successfully!"
    Write-Host ""
    
    # Start development server
    Start-DevServer
}
catch {
    Write-Error "Build failed: $_"
    exit 1
}