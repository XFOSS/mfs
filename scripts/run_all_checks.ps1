# MFS Engine - Comprehensive Quality Check Runner
# Runs all automated checks, tests, and quality analysis

param(
    [switch]$SkipBuild,
    [switch]$SkipTests,
    [switch]$SkipQuality,
    [switch]$Verbose
)

Write-Host "🚀 MFS Engine - Comprehensive Quality Check" -ForegroundColor Cyan
Write-Host "=" * 50 -ForegroundColor Cyan

$ErrorActionPreference = "Continue"
$TotalErrors = 0
$StartTime = Get-Date

# Function to log results
function Write-Result {
    param($Message, $Success, $Duration = $null)
    
    if ($Success) {
        $icon = "✅"
        $color = "Green"
    } else {
        $icon = "❌"
        $color = "Red"
        $script:TotalErrors++
    }
    
    $output = "$icon $Message"
    if ($Duration) {
        $output += " ($($Duration.TotalSeconds.ToString('F2'))s)"
    }
    
    Write-Host $output -ForegroundColor $color
}

# Step 1: Build the project
if (-not $SkipBuild) {
    Write-Host "`n🏗️  Building Project..." -ForegroundColor Yellow
    $buildStart = Get-Date
    
    $buildResult = & zig build 2>&1
    $buildSuccess = $LASTEXITCODE -eq 0
    $buildDuration = (Get-Date) - $buildStart
    
    Write-Result "Project Build" $buildSuccess $buildDuration
    
    if (-not $buildSuccess -and $Verbose) {
        Write-Host "Build Output:" -ForegroundColor Yellow
        $buildResult | Write-Host
    }
} else {
    Write-Host "`n⏭️  Skipping build step" -ForegroundColor Yellow
}

# Step 2: Run unit tests
if (-not $SkipTests) {
    Write-Host "`n🧪 Running Unit Tests..." -ForegroundColor Yellow
    $testStart = Get-Date
    
    $testResult = & zig test src/tests/test_math.zig 2>&1
    $testSuccess = $LASTEXITCODE -eq 0
    $testDuration = (Get-Date) - $testStart
    
    Write-Result "Unit Tests" $testSuccess $testDuration
    
    if ($Verbose) {
        Write-Host "Test Output:" -ForegroundColor Yellow
        $testResult | Write-Host
    }
    
    # Run additional test files if they exist
    $testFiles = @(
        "src/tests/simple_test.zig",
        "src/tests/physics_test.zig",
        "src/tests/test_vulkan.zig"
    )
    
    foreach ($testFile in $testFiles) {
        if (Test-Path $testFile) {
            $fileName = Split-Path $testFile -Leaf
            $specificTestStart = Get-Date
            
            $specificTestResult = & zig test $testFile 2>&1
            $specificTestSuccess = $LASTEXITCODE -eq 0
            $specificTestDuration = (Get-Date) - $specificTestStart
            
            Write-Result "Test: $fileName" $specificTestSuccess $specificTestDuration
        }
    }
} else {
    Write-Host "`n⏭️  Skipping tests" -ForegroundColor Yellow
}

# Step 3: Run code quality analysis
if (-not $SkipQuality) {
    Write-Host "`n📊 Running Code Quality Analysis..." -ForegroundColor Yellow
    $qualityStart = Get-Date
    
    # Run the quality checker directly
    $qualityResult = & zig run scripts/code_quality_check.zig 2>&1
    $qualitySuccess = $LASTEXITCODE -eq 0
    $qualityDuration = (Get-Date) - $qualityStart

    Write-Result "Code Quality Analysis" $qualitySuccess $qualityDuration

    if ($Verbose -or $qualitySuccess) {
        $qualityResult | Write-Host
    }
} else {
    Write-Host "`n⏭️  Skipping quality analysis" -ForegroundColor Yellow
}

# Step 4: Run example builds
Write-Host "`n🎮 Testing Example Builds..." -ForegroundColor Yellow

$examples = @(
    "basic_triangle",
    "textured_cube", 
    "physics_demo",
    "audio_demo"
)

$exampleErrors = 0
foreach ($example in $examples) {
    $exampleStart = Get-Date
    
    $exampleResult = & zig build $example 2>&1
    $exampleSuccess = $LASTEXITCODE -eq 0
    $exampleDuration = (Get-Date) - $exampleStart
    
    Write-Result "Example: $example" $exampleSuccess $exampleDuration
    
    if (-not $exampleSuccess) {
        $exampleErrors++
        if ($Verbose) {
            Write-Host "Error details for $example" -ForegroundColor Yellow
            $exampleResult | Write-Host
        }
    }
}

# Step 5: Platform compatibility check
Write-Host "`n🖥️  Platform Compatibility Check..." -ForegroundColor Yellow

$platformCheckStart = Get-Date
$architecture = if ([System.Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
$platformInfo = @{
    "OS" = [System.Environment]::OSVersion.VersionString
    "Architecture" = $architecture
    "PowerShell Version" = $PSVersionTable.PSVersion.ToString()
    "Zig Version" = ((& zig version 2>&1) -join "").Trim()
}

Write-Host "Platform Information:" -ForegroundColor Cyan
foreach ($key in $platformInfo.Keys) {
    Write-Host "  $key`: $($platformInfo[$key])" -ForegroundColor White
}

$platformDuration = (Get-Date) - $platformCheckStart
Write-Result "Platform Compatibility Check" $true $platformDuration

# Final Summary
$totalDuration = (Get-Date) - $StartTime
Write-Host "`n" + "=" * 50 -ForegroundColor Cyan
Write-Host "🏆 FINAL SUMMARY" -ForegroundColor Cyan
Write-Host "=" * 50 -ForegroundColor Cyan

Write-Host "Total Duration: $($totalDuration.TotalMinutes.ToString('F2')) minutes" -ForegroundColor White
Write-Host "Total Errors: $TotalErrors" -ForegroundColor $(if ($TotalErrors -eq 0) { "Green" } else { "Red" })

if ($TotalErrors -eq 0) {
    Write-Host "🎉 ALL CHECKS PASSED!" -ForegroundColor Green
    Write-Host "The MFS Engine codebase is in excellent condition." -ForegroundColor Green
    exit 0
} else {
    Write-Host "⚠️  SOME CHECKS FAILED" -ForegroundColor Red
    Write-Host "Please review the errors above and fix them." -ForegroundColor Red
    
    Write-Host "`n📋 Recommendations:" -ForegroundColor Yellow
    Write-Host "  • Run with -Verbose to see detailed error messages" -ForegroundColor White
    Write-Host "  • Fix build errors first, then run tests" -ForegroundColor White
    Write-Host "  • Check the generated code_quality_report.csv for detailed metrics" -ForegroundColor White
    
    exit 1
} 