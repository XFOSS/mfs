# Quick MFS Engine Status Check

Write-Host "🚀 MFS Engine Status Check" -ForegroundColor Cyan
Write-Host "=" * 40 -ForegroundColor Cyan

# Check main build
Write-Host "`n🏗️  Main Build..." -ForegroundColor Yellow
$buildResult = & zig build 2>&1
$buildSuccess = $LASTEXITCODE -eq 0
if ($buildSuccess) {
    Write-Host "✅ Main build: SUCCESS" -ForegroundColor Green
} else {
    Write-Host "❌ Main build: FAILED" -ForegroundColor Red
    Write-Host "Error details:" -ForegroundColor Yellow
    $buildResult | Write-Host
}

# Check available build steps
Write-Host "`n📋 Available Build Steps..." -ForegroundColor Yellow
$buildList = & zig build -l 2>&1
Write-Host $buildList

# Test graphics tests
Write-Host "`n🎮 Graphics Tests..." -ForegroundColor Yellow
$testResult = & zig build test-graphics 2>&1
$testSuccess = $LASTEXITCODE -eq 0
if ($testSuccess) {
    Write-Host "✅ Graphics tests: SUCCESS" -ForegroundColor Green
} else {
    Write-Host "❌ Graphics tests: FAILED" -ForegroundColor Red
    Write-Host "Error details:" -ForegroundColor Yellow
    $testResult | Write-Host
}

Write-Host "`n🏆 Summary:" -ForegroundColor Cyan
Write-Host "- Main Engine Build: $(if ($buildSuccess) { 'PASS' } else { 'FAIL' })" -ForegroundColor $(if ($buildSuccess) { 'Green' } else { 'Red' })
Write-Host "- Graphics Tests: $(if ($testSuccess) { 'PASS' } else { 'FAIL' })" -ForegroundColor $(if ($testSuccess) { 'Green' } else { 'Red' })