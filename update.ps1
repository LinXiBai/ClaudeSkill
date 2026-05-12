# update.ps1 - 拉取最新版并重新安装
$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "==> Pulling latest changes..." -ForegroundColor Cyan
Push-Location $PSScriptRoot
try {
    git pull
} finally {
    Pop-Location
}

Write-Host ""
& (Join-Path $PSScriptRoot "install.ps1")
