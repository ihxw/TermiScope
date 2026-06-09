# Go to project root directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)
Set-Location $ProjectRoot

cd .\web
npm install
npm run build   
cd ..

# . "$PSScriptRoot\..\..\build_agents.ps1"

$PackageJson = Get-Content "web/package.json" | ConvertFrom-Json
$Version = $PackageJson.version
Write-Host "Starting Server v$Version..."

go run -ldflags "-X main.Version=$Version" cmd/server/main.go
