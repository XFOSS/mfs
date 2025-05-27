# Complete Vulkan SDK Installation Script for Windows
# This script downloads and installs the full Vulkan SDK with development headers and libraries

param(
    [string]$Version = "1.4.309.0",
    [string]$InstallPath = "C:\VulkanSDK",
    [switch]$Force
)

Write-Host "=== Complete Vulkan SDK Installation ===" -ForegroundColor Green
Write-Host "Version: $Version" -ForegroundColor Yellow
Write-Host "Install Path: $InstallPath" -ForegroundColor Yellow

# Check if running as administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Error: This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "Please right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    exit 1
}

# Create temporary directory
$TempDir = "$env:TEMP\vulkan_install"
if (Test-Path $TempDir) {
    Remove-Item $TempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

try {
    # Download URL for complete Vulkan SDK
    $DownloadUrl = "https://sdk.lunarg.com/sdk/download/$Version/windows/VulkanSDK-$Version-Installer.exe"
    $InstallerPath = "$TempDir\VulkanSDK-$Version-Installer.exe"
    
    Write-Host "Downloading Vulkan SDK $Version..." -ForegroundColor Yellow
    Write-Host "URL: $DownloadUrl" -ForegroundColor Gray
    
    # Download with progress
    $ProgressPreference = 'Continue'
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $InstallerPath -UseBasicParsing
    
    if (-not (Test-Path $InstallerPath)) {
        throw "Download failed - installer not found"
    }
    
    $FileSize = (Get-Item $InstallerPath).Length / 1MB
    Write-Host "Downloaded: $([math]::Round($FileSize, 2)) MB" -ForegroundColor Green
    
    # Check if Vulkan SDK already exists
    $ExistingInstall = "$InstallPath\$Version"
    if (Test-Path $ExistingInstall) {
        if ($Force) {
            Write-Host "Removing existing installation..." -ForegroundColor Yellow
            Remove-Item $ExistingInstall -Recurse -Force
        } else {
            Write-Host "Vulkan SDK $Version already exists at $ExistingInstall" -ForegroundColor Yellow
            Write-Host "Use -Force to reinstall" -ForegroundColor Gray
            exit 0
        }
    }
    
    # Install Vulkan SDK silently with all components
    Write-Host "Installing Vulkan SDK..." -ForegroundColor Yellow
    Write-Host "This may take several minutes..." -ForegroundColor Gray
    
    $InstallArgs = @(
        "/S",  # Silent install
        "/D=$InstallPath\$Version"  # Installation directory
    )
    
    $Process = Start-Process -FilePath $InstallerPath -ArgumentList $InstallArgs -Wait -PassThru
    
    if ($Process.ExitCode -ne 0) {
        throw "Installation failed with exit code: $($Process.ExitCode)"
    }
    
    Write-Host "Installation completed successfully!" -ForegroundColor Green
    
    # Verify installation
    Write-Host "Verifying installation..." -ForegroundColor Yellow
    
    $SdkPath = "$InstallPath\$Version"
    $RequiredDirs = @("Include", "Lib", "Bin", "Config")
    $MissingDirs = @()
    
    foreach ($Dir in $RequiredDirs) {
        $DirPath = "$SdkPath\$Dir"
        if (-not (Test-Path $DirPath)) {
            $MissingDirs += $Dir
        } else {
            Write-Host "✓ $Dir directory found" -ForegroundColor Green
        }
    }
    
    if ($MissingDirs.Count -gt 0) {
        Write-Host "Warning: Missing directories: $($MissingDirs -join ', ')" -ForegroundColor Red
        Write-Host "Installation may be incomplete" -ForegroundColor Yellow
    }
    
    # Check for key files
    $KeyFiles = @(
        "$SdkPath\Include\vulkan\vulkan.h",
        "$SdkPath\Lib\vulkan-1.lib",
        "$SdkPath\Bin\vulkaninfo.exe"
    )
    
    foreach ($File in $KeyFiles) {
        if (Test-Path $File) {
            Write-Host "✓ $(Split-Path $File -Leaf) found" -ForegroundColor Green
        } else {
            Write-Host "✗ $(Split-Path $File -Leaf) missing" -ForegroundColor Red
        }
    }
    
    # Set environment variables
    Write-Host "Setting environment variables..." -ForegroundColor Yellow
    
    $VulkanSdkPath = $SdkPath
    $VulkanBinPath = "$SdkPath\Bin"
    
    # Set VULKAN_SDK
    [Environment]::SetEnvironmentVariable("VULKAN_SDK", $VulkanSdkPath, "Machine")
    Write-Host "✓ VULKAN_SDK = $VulkanSdkPath" -ForegroundColor Green
    
    # Add to PATH
    $CurrentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
    if ($CurrentPath -notlike "*$VulkanBinPath*") {
        $NewPath = "$CurrentPath;$VulkanBinPath"
        [Environment]::SetEnvironmentVariable("PATH", $NewPath, "Machine")
        Write-Host "✓ Added to PATH: $VulkanBinPath" -ForegroundColor Green
    } else {
        Write-Host "✓ PATH already contains Vulkan Bin directory" -ForegroundColor Green
    }
    
    # Set VK_LAYER_PATH for validation layers
    $LayerPath = "$SdkPath\Bin"
    [Environment]::SetEnvironmentVariable("VK_LAYER_PATH", $LayerPath, "Machine")
    Write-Host "✓ VK_LAYER_PATH = $LayerPath" -ForegroundColor Green
    
    # Test vulkaninfo
    Write-Host "Testing Vulkan installation..." -ForegroundColor Yellow
    
    # Update PATH for current session
    $env:PATH = "$env:PATH;$VulkanBinPath"
    $env:VULKAN_SDK = $VulkanSdkPath
    
    try {
        $VulkanInfo = & "$VulkanBinPath\vulkaninfo.exe" --summary 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ vulkaninfo executed successfully" -ForegroundColor Green
            Write-Host "Vulkan is working correctly!" -ForegroundColor Green
        } else {
            Write-Host "⚠ vulkaninfo reported issues (exit code: $LASTEXITCODE)" -ForegroundColor Yellow
            Write-Host "This may indicate driver or hardware issues" -ForegroundColor Gray
        }
    } catch {
        Write-Host "⚠ Could not execute vulkaninfo: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    Write-Host "`n=== Installation Summary ===" -ForegroundColor Green
    Write-Host "Vulkan SDK Version: $Version" -ForegroundColor White
    Write-Host "Installation Path: $SdkPath" -ForegroundColor White
    Write-Host "Environment Variables Set:" -ForegroundColor White
    Write-Host "  VULKAN_SDK = $VulkanSdkPath" -ForegroundColor Gray
    Write-Host "  VK_LAYER_PATH = $LayerPath" -ForegroundColor Gray
    Write-Host "  PATH updated with Vulkan binaries" -ForegroundColor Gray
    
    Write-Host "`nNext Steps:" -ForegroundColor Yellow
    Write-Host "1. Restart your terminal/IDE to pick up environment changes" -ForegroundColor White
    Write-Host "2. Run 'zig build check-vulkan' to verify Zig integration" -ForegroundColor White
    Write-Host "3. Run 'zig build vulkan-working' to test Vulkan renderer" -ForegroundColor White
    
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    # Cleanup
    if (Test-Path $TempDir) {
        Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}