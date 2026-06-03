# Build Agents Helper with Version Injection (Multi-platform / Multi-arch)
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

# Define targets (GOOS, GOARCH, optional GOARM, output name)
$targets = @(
    @{os='linux'; arch='amd64'; arm=$null; out='termiscope-agent-linux-amd64'},
    @{os='linux'; arch='arm64'; arm=$null; out='termiscope-agent-linux-arm64'},
    @{os='linux'; arch='arm'; arm='7'; out='termiscope-agent-linux-armv7'},
    @{os='linux'; arch='386'; arm=$null; out='termiscope-agent-linux-386'},

    @{os='darwin'; arch='amd64'; arm=$null; out='termiscope-agent-darwin-amd64'},
    @{os='darwin'; arch='arm64'; arm=$null; out='termiscope-agent-darwin-arm64'},

    @{os='windows'; arch='amd64'; arm=$null; out='termiscope-agent-windows-amd64.exe'},
    @{os='windows'; arch='arm64'; arm=$null; out='termiscope-agent-windows-arm64.exe'},
    @{os='windows'; arch='386'; arm=$null; out='termiscope-agent-windows-386.exe'}
)

foreach ($t in $targets) {
    $goos = $t.os
    $goarch = $t.arch
    $goarm = $t.arm
    $outfile = Join-Path $AgentDir $t.out

    Write-Host "Building $goos/$goarch -> $outfile"

    # Set environment for build
    $env:GOOS = $goos
    $env:GOARCH = $goarch
    if ($goarm) { $env:GOARM = $goarm } else { Remove-Item Env:\GOARM -ErrorAction SilentlyContinue }

    # Ensure Windows executables get .exe suffix
    try {
        go build -ldflags $LdFlags -o $outfile ./cmd/agent
        Write-Host "Built: $outfile"
    } catch {
        Write-Warning "Build failed for $goos/$goarch : $($_.Exception.Message)"
    }
}

# Reset Env
Remove-Item Env:\GOOS -ErrorAction SilentlyContinue
Remove-Item Env:\GOARCH -ErrorAction SilentlyContinue
Remove-Item Env:\GOARM -ErrorAction SilentlyContinue

Write-Host "Agents v$Version built (where supported) in $AgentDir/" -ForegroundColor Green
Get-ChildItem $AgentDir
