# Build Agents Helper
$ErrorActionPreference = "Stop"

$AgentDir = "agents"
if (-not (Test-Path $AgentDir)) {
    New-Item -ItemType Directory -Path $AgentDir | Out-Null
}

Write-Host "Building TermiScope Agents..." -ForegroundColor Cyan

# Linux AMD64
Write-Host "Building linux/amd64..."
$env:GOOS = "linux"
$env:GOARCH = "amd64"
go build -o "$AgentDir/termiscope-agent-linux-amd64" ./cmd/agent

$env:GOOS = "linux"
$env:GOARCH = "arm64"
go build -o "$AgentDir/termiscope-agent-linux-arm64" ./cmd/agent

$env:GOOS = "linux"
$env:GOARCH = "arm"
$env:GOARM = "7"
go build -o "$AgentDir/termiscope-agent-linux-armv7" ./cmd/agent

$env:GOOS = "windows"
$env:GOARCH = "amd64"
go build -o "$AgentDir/termiscope-agent-windows-amd64.exe" ./cmd/agent

$env:GOOS = "darwin"
$env:GOARCH = "amd64"
go build -o "$AgentDir/termiscope-agent-darwin-amd64" ./cmd/agent

$env:GOOS = "darwin"
$env:GOARCH = "arm64"
go build -o "$AgentDir/termiscope-agent-darwin-arm64" ./cmd/agent

# Reset Env
Remove-Item Env:\GOOS -ErrorAction SilentlyContinue
Remove-Item Env:\GOARCH -ErrorAction SilentlyContinue
Remove-Item Env:\GOARM -ErrorAction SilentlyContinue

Write-Host "Agents built successfully in $AgentDir/" -ForegroundColor Green
Get-ChildItem $AgentDir
