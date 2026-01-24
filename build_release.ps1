# TermiScope Release Build Script
# usage: .\build_release.ps1

$ErrorActionPreference = "Stop"

# Configuration
$AppName = "TermiScope"
$Version = "1.0.0" # You might want to extract this from config or git tags later
$ReleaseDir = Join-Path $PSScriptRoot "release"
$WebDir = Join-Path $PSScriptRoot "web"
$BinDir = Join-Path $PSScriptRoot "bin"
$DistDir = Join-Path $WebDir "dist"

# Platforms to build for
$Targets = @(
    @{ OS = "windows"; Arch = "amd64"; Ext = ".exe"; Archive = "zip" },
    @{ OS = "linux"; Arch = "amd64"; Ext = ""; Archive = "tar.gz" },
    @{ OS = "linux"; Arch = "arm64"; Ext = ""; Archive = "tar.gz" },
    @{ OS = "darwin"; Arch = "amd64"; Ext = ""; Archive = "tar.gz" },
    @{ OS = "darwin"; Arch = "arm64"; Ext = ""; Archive = "tar.gz" }
)

Write-Host "Starting TermiScope Release Build..." -ForegroundColor Cyan

# 1. Environment Check
Write-Host "1. Checking environment..." -ForegroundColor Yellow
if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
    Write-Error "Go is not installed."
}
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Error "Node.js (npm) is not installed."
}
# Check for tar command availability for non-Windows archives
if (-not (Get-Command tar -ErrorAction SilentlyContinue)) {
    Write-Warning "tar command not found. Non-Windows builds typically require tar for .tar.gz. Will attempt to use it anyway."
}

# 2. Cleanup
Write-Host "2. Cleaning up..." -ForegroundColor Yellow
if (Test-Path $ReleaseDir) { Remove-Item -Recurse -Force $ReleaseDir }
New-Item -ItemType Directory -Path $ReleaseDir | Out-Null
if (Test-Path $BinDir) { Remove-Item -Recurse -Force $BinDir }

# 3. Build Frontend
Write-Host "3. Building Frontend..." -ForegroundColor Yellow
Push-Location $WebDir
try {
    Write-Host "   Installing dependencies..."
    npm install | Out-Null
    Write-Host "   Building assets..."
    npm run build | Out-Null
}
finally {
    Pop-Location
}

if (-not (Test-Path $DistDir)) {
    Write-Error "Frontend build failed: dist directory not found."
}

# 3.5 Build Agents
Write-Host "3.5 Building Agents..." -ForegroundColor Yellow

# Read version from package.json
$PackageJson = Get-Content (Join-Path $WebDir "package.json") | ConvertFrom-Json
$AgentVersion = $PackageJson.version
Write-Host "   Agent Version: $AgentVersion"

$AgentDir = Join-Path $PSScriptRoot "agents"
if (-not (Test-Path $AgentDir)) { New-Item -ItemType Directory -Path $AgentDir | Out-Null }

# Build flags to inject version
$AgentLdFlags = "-X main.Version=$AgentVersion"

# Create a README for agents
$AgentReadme = @"
TermiScope Monitoring Agent
===========================

Supported OS:
- Linux (amd64, arm64, armv7)
- Windows (amd64)
- macOS (amd64, arm64)

Installation:
1. Upload/Copy the appropriate binary to your server/machine.
2. Make it executable (Linux/macOS): chmod +x termiscope-agent-*
3. Run it via TermiScope Dashboard "Deploy" button (Linux) or manually:

   Linux/macOS:
   ./termiscope-agent-[os]-[arch] -server http://YOUR_SERVER:3000 -secret YOUR_SECRET -id HOST_ID

   Windows (PowerShell/CMD):
   .\termiscope-agent-windows-amd64.exe -server http://YOUR_SERVER:3000 -secret YOUR_SECRET -id HOST_ID
"@
$AgentReadme | Set-Content (Join-Path $AgentDir "README.txt")

# Agent Linux AMD64
Write-Host "   Building Agent linux/amd64..."
$Env:GOOS = "linux"; $Env:GOARCH = "amd64"
go build -ldflags $AgentLdFlags -o (Join-Path $AgentDir "termiscope-agent-linux-amd64") ./cmd/agent

# Agent Linux ARM64
Write-Host "   Building Agent linux/arm64..."
$Env:GOOS = "linux"; $Env:GOARCH = "arm64"
go build -ldflags $AgentLdFlags -o (Join-Path $AgentDir "termiscope-agent-linux-arm64") ./cmd/agent
# Agent Linux ARM (v7)
Write-Host "   Building Agent linux/arm..."
$Env:GOOS = "linux"; $Env:GOARCH = "arm"; $Env:GOARM = "7"
go build -ldflags $AgentLdFlags -o (Join-Path $AgentDir "termiscope-agent-linux-arm") ./cmd/agent

# Agent Windows AMD64
Write-Host "   Building Agent windows/amd64..."
$Env:GOOS = "windows"; $Env:GOARCH = "amd64"
go build -ldflags $AgentLdFlags -o (Join-Path $AgentDir "termiscope-agent-windows-amd64.exe") ./cmd/agent

# Agent Darwin AMD64 (Intel)
Write-Host "   Building Agent darwin/amd64..."
$Env:GOOS = "darwin"; $Env:GOARCH = "amd64"
go build -ldflags $AgentLdFlags -o (Join-Path $AgentDir "termiscope-agent-darwin-amd64") ./cmd/agent

# Agent Darwin ARM64 (Apple Silicon)
Write-Host "   Building Agent darwin/arm64..."
$Env:GOOS = "darwin"; $Env:GOARCH = "arm64"
go build -ldflags $AgentLdFlags -o (Join-Path $AgentDir "termiscope-agent-darwin-arm64") ./cmd/agent

# Reset Env
Remove-Item Env:\GOOS -ErrorAction SilentlyContinue
Remove-Item Env:\GOARCH -ErrorAction SilentlyContinue

# 4. Build and Package for each target
Write-Host "4. Building Backends and Packaging..." -ForegroundColor Yellow

foreach ($Target in $Targets) {
    $OS = $Target.OS
    $Arch = $Target.Arch
    $Ext = $Target.Ext
    $ArchiveType = $Target.Archive
    
    $PackageName = "$AppName-$Version-$OS-$Arch"
    $OutputDir = Join-Path $ReleaseDir $PackageName
    $BinaryName = "$AppName$Ext"
    $BinaryPath = Join-Path $OutputDir $BinaryName

    Write-Host "   Building for $OS/$Arch..."
    
    # Create temp directory for this target
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
    
    # Copy Assets
    $WebDistDest = Join-Path $OutputDir "web/dist"
    New-Item -ItemType Directory -Path (Split-Path $WebDistDest) -Force | Out-Null
    Copy-Item -Recurse -Path $DistDir -Destination (Split-Path $WebDistDest)

    # Copy Configs
    $ConfigDest = Join-Path $OutputDir "configs"
    New-Item -ItemType Directory -Path $ConfigDest | Out-Null
    Copy-Item -Path (Join-Path $PSScriptRoot "configs/config.yaml") -Destination $ConfigDest

    # Copy Agents
    $AgentDest = Join-Path $OutputDir "agents"
    New-Item -ItemType Directory -Path $AgentDest | Out-Null
    Copy-Item -Path "$AgentDir/*" -Destination $AgentDest

    # Copy LICENSE
    Copy-Item -Path (Join-Path $PSScriptRoot "LICENSE") -Destination $OutputDir

    # Linux-specific: Copy Install Scripts
    if ($OS -eq "linux") {
        $ScriptDir = Join-Path $PSScriptRoot "scripts"
        if (Test-Path $ScriptDir) {
            $Scripts = @("install.sh", "uninstall.sh")
            foreach ($Script in $Scripts) {
                $Src = Join-Path $ScriptDir $Script
                if (Test-Path $Src) {
                    $Dest = Join-Path $OutputDir $Script
                    # Read content and replace CRLF with LF to ensure Linux compatibility
                    $Content = Get-Content $Src -Raw
                    $Content = $Content -replace "`r`n", "`n"
                    # Write with NO BOM and LF
                    [System.IO.File]::WriteAllText($Dest, $Content)
                }
            }
        }
    }

    # Build Go Binary
    $Env:GOOS = $OS
    $Env:GOARCH = $Arch
    $Env:CGO_ENABLED = "0"
    
    # Read version from package.json
    $PackageJson = Get-Content (Join-Path $WebDir "package.json") | ConvertFrom-Json
    $Version = $PackageJson.version
    Write-Host "   Using Version: $Version"

    go build -ldflags "-X 'github.com/ihxw/termiscope/internal/config.Version=$Version'" -o $BinaryPath ./cmd/server/main.go
    
    if (-not (Test-Path $BinaryPath)) {
        Write-Error "Build failed for $OS/$Arch"
    }

    # Archive
    Write-Host "   Packaging $PackageName..."
    $ArchivePath = Join-Path $ReleaseDir "$PackageName.$ArchiveType"
    
    if ($ArchiveType -eq "zip") {
        Compress-Archive -Path "$OutputDir\*" -DestinationPath $ArchivePath
    }
    elseif ($ArchiveType -eq "tar.gz") {
        # Using tar.exe (available on Windows 10/11)
        # -C changes directory so we archive the *contents* of OutputDir relative to it, or just archive the folder itself?
        # Standard practice: archive the folder so when extracted it creates a folder.
        # Let's archive the folder relative to ReleaseDir
        
        $CurrentDir = Get-Location
        Set-Location $ReleaseDir
        try {
            tar -czf "$PackageName.tar.gz" $PackageName
        }
        finally {
            Set-Location $CurrentDir
        }
    }

    # Cleanup temp folder for this target
    Remove-Item -Recurse -Force $OutputDir
    
    Write-Host "   Done: $ArchivePath" -ForegroundColor Green
}

# Cleanup Env Vars
Remove-Item Env:\GOOS -ErrorAction SilentlyContinue
Remove-Item Env:\GOARCH -ErrorAction SilentlyContinue
Remove-Item Env:\GOARM -ErrorAction SilentlyContinue
Remove-Item Env:\CGO_ENABLED -ErrorAction SilentlyContinue

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Release build complete!" -ForegroundColor Green
Write-Host "Artifacts are in: $ReleaseDir" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
