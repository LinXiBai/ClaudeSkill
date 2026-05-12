# install.ps1 - Claude Skills 一键安装
$ErrorActionPreference = "Stop"

$skillsDir = "$env:USERPROFILE\.claude\skills"
$srcDir = Join-Path $PSScriptRoot "skills"

if (-not (Test-Path $srcDir)) {
    Write-Host "ERROR: skills folder not found at $srcDir" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "==> Installing Claude Skills to: $skillsDir" -ForegroundColor Cyan
Write-Host ""

New-Item -ItemType Directory -Force -Path $skillsDir | Out-Null

$count = 0
Get-ChildItem $srcDir -Directory | ForEach-Object {
    $skillName = $_.Name
    Write-Host "  - $skillName" -ForegroundColor Green
    Copy-Item -Recurse -Force $_.FullName $skillsDir
    $count++
}

Write-Host ""
Write-Host "==> Installed $count skill(s)." -ForegroundColor Cyan
Write-Host ""
Write-Host "Verify:" -ForegroundColor Yellow
Write-Host "  1. Open a NEW Claude Code session (claude command)"
Write-Host "  2. Type:  /skills"
Write-Host "  3. You should see the installed skills listed"
Write-Host ""
