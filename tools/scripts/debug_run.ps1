
Write-Host "Cleaning up old processes..."
Stop-Process -Name "main" -ErrorAction SilentlyContinue
Stop-Process -Name "server" -ErrorAction SilentlyContinue

# Go to project root directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)
Set-Location $ProjectRoot

Write-Host "Building Server..."
go build -o server.exe .\cmd\server\main.go
if ($LastExitCode -ne 0) {
    Write-Error "Build failed!"
    exit 1
}

Write-Host "Starting Server..."
.\server.exe
