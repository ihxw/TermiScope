# Build Agents Helper with Version Injection
$ErrorActionPreference = "Stop"

# Read version from package.json
$PackageJson = Get-Content "web/package.json" | ConvertFrom-Json
$Version = $PackageJson.version

Write-Host "Building TermiScope Agents v$Version..." -ForegroundColor Cyan

$AgentDir = "agents"
if (-not (Test-Path $AgentDir)) {
    New-Item -ItemType Directory -Path $AgentDir | Out-Null
}

# Build flags to inject version
$LdFlags = "-X main.Version=$Version"

# Linux AMD64
Write-Host "Building linux/amd64..."
$env:GOOS = "linux"
$env:GOARCH = "amd64"
go build -ldflags $LdFlags -o "$AgentDir/termiscope-agent-linux-amd64" ./cmd/agent

# Linux ARM64
Write-Host "Building linux/arm64..."
$env:GOOS = "linux"
$env:GOARCH = "arm64"
go build -ldflags $LdFlags -o "$AgentDir/termiscope-agent-linux-arm64" ./cmd/agent

# Linux ARMv7
Write-Host "Building linux/armv7..."
$env:GOOS = "linux"
$env:GOARCH = "arm"
$env:GOARM = "7"
go build -ldflags $LdFlags -o "$AgentDir/termiscope-agent-linux-armv7" ./cmd/agent

# Windows AMD64
Write-Host "Building windows/amd64..."
$env:GOOS = "windows"
$env:GOARCH = "amd64"
go build -ldflags $LdFlags -o "$AgentDir/termiscope-agent-windows-amd64.exe" ./cmd/agent

# macOS AMD64
Write-Host "Building darwin/amd64..."
$env:GOOS = "darwin"
$env:GOARCH = "amd64"
go build -ldflags $LdFlags -o "$AgentDir/termiscope-agent-darwin-amd64" ./cmd/agent

# macOS ARM64 (Apple Silicon)
Write-Host "Building darwin/arm64..."
$env:GOOS = "darwin"
$env:GOARCH = "arm64"
go build -ldflags $LdFlags -o "$AgentDir/termiscope-agent-darwin-arm64" ./cmd/agent

# Reset Env
Remove-Item Env:\GOOS -ErrorAction SilentlyContinue
Remove-Item Env:\GOARCH -ErrorAction SilentlyContinue
Remove-Item Env:\GOARM -ErrorAction SilentlyContinue

Write-Host "Agents v$Version built successfully in $AgentDir/" -ForegroundColor Green
Get-ChildItem $AgentDir
