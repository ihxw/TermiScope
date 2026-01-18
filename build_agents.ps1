# Build Agents Helper
$ErrorActionPreference = "Stop"

$AgentDir = "agents"
if (-not (Test-Path $AgentDir)) {
    New-Item -ItemType Directory -Path $AgentDir | Out-Null
}

Write-Host "Building TermiScope Agents..." -ForegroundColor Cyan

# Linux AMD64
Write-Host "Building linux/amd64..."
$Env:GOOS = "linux"
$Env:GOARCH = "amd64"
go build -o "$AgentDir/termiscope-agent-linux-amd64" ./cmd/agent

# Linux ARM64
Write-Host "Building linux/arm64..."
$Env:GOOS = "linux"
$Env:GOARCH = "arm64"
go build -o "$AgentDir/termiscope-agent-linux-arm64" ./cmd/agent

# Linux ARM (v7)
Write-Host "Building linux/arm..."
$Env:GOOS = "linux"
$Env:GOARCH = "arm"
$Env:GOARM = "7"
go build -o "$AgentDir/termiscope-agent-linux-arm" ./cmd/agent

# Reset Env
Remove-Item Env:\GOOS -ErrorAction SilentlyContinue
Remove-Item Env:\GOARCH -ErrorAction SilentlyContinue

Write-Host "Agents built successfully in $AgentDir/" -ForegroundColor Green
Get-ChildItem $AgentDir
