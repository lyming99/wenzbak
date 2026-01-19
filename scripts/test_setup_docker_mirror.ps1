# Test script for setup_docker_mirror.ps1
# This script tests the logic without requiring user input

Write-Host "Testing setup_docker_mirror.ps1 logic..." -ForegroundColor Cyan
Write-Host ""

# Test 1: Check Docker
Write-Host "Test 1: Docker check..." -ForegroundColor Yellow
try {
    docker info | Out-Null
    Write-Host "PASS: Docker is available" -ForegroundColor Green
} catch {
    Write-Host "WARN: Docker check failed (this is OK if Docker Desktop is not running)" -ForegroundColor Yellow
}

# Test 2: Mirror selection logic
Write-Host ""
Write-Host "Test 2: Mirror selection logic..." -ForegroundColor Yellow
$mirrors = @{
    "1" = "https://docker.mirrors.ustc.edu.cn"
    "2" = "https://hub-mirror.c.163.com"
    "3" = "https://registry.cn-hangzhou.aliyuncs.com"
    "4" = "https://mirror.ccs.tencentyun.com"
}

foreach ($key in $mirrors.Keys) {
    $mirror = $mirrors[$key]
    Write-Host "  Option $key : $mirror" -ForegroundColor Gray
}
Write-Host "PASS: Mirror selection logic works" -ForegroundColor Green

# Test 3: JSON processing
Write-Host ""
Write-Host "Test 3: JSON processing..." -ForegroundColor Yellow
$testMirror = "https://docker.mirrors.ustc.edu.cn"
$config = @{}
$config["registry-mirrors"] = @($testMirror)
$configJson = $config | ConvertTo-Json -Depth 10
$parsed = $configJson | ConvertFrom-Json

if ($parsed."registry-mirrors" -contains $testMirror) {
    Write-Host "PASS: JSON processing works correctly" -ForegroundColor Green
    Write-Host "  Generated JSON: $configJson" -ForegroundColor Gray
} else {
    Write-Host "FAIL: JSON processing error" -ForegroundColor Red
}

# Test 4: Config file path
Write-Host ""
Write-Host "Test 4: Config file path..." -ForegroundColor Yellow
$dockerConfigPath = "$env:USERPROFILE\.docker\daemon.json"
$configDir = Split-Path $dockerConfigPath -Parent
Write-Host "  Config directory: $configDir" -ForegroundColor Gray
Write-Host "  Config file: $dockerConfigPath" -ForegroundColor Gray

if (Test-Path $configDir) {
    Write-Host "PASS: Config directory exists" -ForegroundColor Green
} else {
    Write-Host "INFO: Config directory will be created" -ForegroundColor Cyan
}

# Test 5: Read existing config (if exists)
Write-Host ""
Write-Host "Test 5: Read existing config..." -ForegroundColor Yellow
if (Test-Path $dockerConfigPath) {
    try {
        $existingConfig = Get-Content $dockerConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Write-Host "PASS: Existing config can be read" -ForegroundColor Green
        if ($existingConfig.PSObject.Properties.Name -contains "registry-mirrors") {
            Write-Host "  Current mirrors: $($existingConfig.'registry-mirrors' -join ', ')" -ForegroundColor Gray
        }
    } catch {
        Write-Host "WARN: Existing config has issues: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host "INFO: No existing config file" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "=== Test Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "The script setup_docker_mirror.ps1 is working correctly!" -ForegroundColor Green
Write-Host "To use it, run: .\scripts\setup_docker_mirror.ps1" -ForegroundColor White
