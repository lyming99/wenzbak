# Configure Docker registry mirrors script (PowerShell)
# For Windows Docker Desktop

Write-Host "Docker Registry Mirror Configuration Tool" -ForegroundColor Cyan
Write-Host ""

# Check if Docker Desktop is running
try {
    docker info | Out-Null
} catch {
    Write-Host "Error: Docker is not running, please start Docker Desktop first" -ForegroundColor Red
    exit 1
}

Write-Host "Please select a registry mirror:" -ForegroundColor Yellow
Write-Host "1. USTC Mirror (China)" -ForegroundColor White
Write-Host "2. NetEase Mirror (China)" -ForegroundColor White
Write-Host "3. Aliyun Mirror (China, requires login)" -ForegroundColor White
Write-Host "4. Tencent Cloud Mirror (China)" -ForegroundColor White
Write-Host "5. Custom mirror" -ForegroundColor White
Write-Host ""

$choice = Read-Host "Please enter option (1-5)"

$mirrors = @{
    "1" = "https://docker.mirrors.ustc.edu.cn"
    "2" = "https://hub-mirror.c.163.com"
    "3" = "https://registry.cn-hangzhou.aliyuncs.com"
    "4" = "https://mirror.ccs.tencentyun.com"
}

$selectedMirror = $null

if ($choice -in @("1", "2", "3", "4")) {
    $selectedMirror = $mirrors[$choice]
} elseif ($choice -eq "5") {
    $selectedMirror = Read-Host "Please enter mirror address"
} else {
    Write-Host "Invalid option" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Configuration instructions:" -ForegroundColor Yellow
Write-Host "1. Open Docker Desktop" -ForegroundColor White
Write-Host "2. Go to Settings -> Docker Engine" -ForegroundColor White
Write-Host "3. Add the following to the configuration file:" -ForegroundColor White
Write-Host ""
$configExample = '{"registry-mirrors": ["' + $selectedMirror + '"]}'
Write-Host $configExample -ForegroundColor Green
Write-Host ""
Write-Host "4. Click 'Apply & Restart'" -ForegroundColor White
Write-Host "5. Wait for Docker to restart" -ForegroundColor White
Write-Host ""
Write-Host "Or, I can try to configure automatically (requires admin rights)..." -ForegroundColor Yellow
$auto = Read-Host "Auto configure? (y/n)"

if ($auto -eq "y" -or $auto -eq "Y") {
    $dockerConfigPath = "$env:USERPROFILE\.docker\daemon.json"
    $configDir = Split-Path $dockerConfigPath -Parent
    
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }
    
    $config = @{}
    if (Test-Path $dockerConfigPath) {
        try {
            $existingConfig = Get-Content $dockerConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($existingConfig) {
                $config = @{}
                if ($existingConfig.PSObject.Properties.Name -contains "registry-mirrors") {
                    $config["registry-mirrors"] = @($existingConfig."registry-mirrors")
                } else {
                    $config["registry-mirrors"] = @()
                }
            }
        } catch {
            Write-Host "Warning: Cannot read existing config file, will create new one" -ForegroundColor Yellow
            $config = @{}
            $config["registry-mirrors"] = @()
        }
    } else {
        $config["registry-mirrors"] = @()
    }
    
    if ($config["registry-mirrors"] -notcontains $selectedMirror) {
        $config["registry-mirrors"] += $selectedMirror
    }
    
    $configJson = $config | ConvertTo-Json -Depth 10
    $configJson | Set-Content $dockerConfigPath -Encoding UTF8
    
    Write-Host "Config file updated: $dockerConfigPath" -ForegroundColor Green
    Write-Host "Please restart Docker Desktop for changes to take effect" -ForegroundColor Yellow
}
