# Build TermiScope linux/amd64 on Windows, then install into WSL.
# Existing database and config under the install directory are preserved.
#
# Usage:
#   .\scripts\build_and_install_wsl.ps1
#   .\scripts\build_and_install_wsl.ps1 -SkipWeb
#   .\scripts\build_and_install_wsl.ps1 -BuildOnly
#   .\scripts\build_and_install_wsl.ps1 -InstallDir /opt/termiscope

param(
    [switch]$SkipWeb,
    [switch]$BuildOnly,
    [string]$InstallDir = "/opt/termiscope",
    [string]$Port = "",
    [string]$WslDistro = ""
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

function Convert-ToWslPath([string]$WindowsPath) {
    $resolved = (Resolve-Path $WindowsPath -ErrorAction Stop).Path
    if ($resolved -match '^([A-Za-z]):\\(.*)$') {
        $drive = $Matches[1].ToLower()
        $rest = $Matches[2] -replace '\\', '/'
        return "/mnt/$drive/$rest"
    }
    return $resolved -replace '\\', '/'
}

function Invoke-Wsl([string]$Command) {
    $wslArgs = @()
    if ($WslDistro) {
        $wslArgs += @("-d", $WslDistro)
    }
    $wslArgs += @("bash", "-lc", $Command)
    & wsl @wslArgs
    if ($LASTEXITCODE -ne 0) { throw "WSL command failed (exit $LASTEXITCODE)" }
}

$buildScript = Join-Path $PSScriptRoot "build_linux_amd64.ps1"
$built = $false
try {
    $buildParams = @{}
    if ($SkipWeb) { $buildParams.SkipWeb = $true }
    & $buildScript @buildParams
    $built = $true
} catch {
    Write-Host "[build] Windows build failed: $_"
    Write-Host "[build] Falling back to WSL build (scripts/build_linux_amd64.sh) ..."
    $wslRoot = Convert-ToWslPath $Root
    $wslBuildCmd = "cd '$wslRoot' && bash scripts/build_linux_amd64.sh"
    if ($SkipWeb) { $wslBuildCmd += " --skip-web" }
    Invoke-Wsl $wslBuildCmd
    $built = $true
}

if (-not $built) { throw "Build did not complete." }

$pkg = Get-Content (Join-Path $Root "web\package.json") -Raw | ConvertFrom-Json
$archiveName = "termiscope-linux-amd64-$($pkg.version).tar.gz"
$archiveWin = Join-Path $Root "release\$archiveName"
if (-not (Test-Path $archiveWin)) {
    throw "Archive not found after build: $archiveWin"
}

Write-Host ""
Write-Host "[install] Package: $archiveWin"

if ($BuildOnly) {
    Write-Host "[install] -BuildOnly set; skipping WSL install."
    Write-Host "Install manually in WSL:"
    Write-Host "  sudo bash scripts/install_wsl.sh $(Convert-ToWslPath $archiveWin) --install-dir $InstallDir -y"
    exit 0
}

$archiveWsl = Convert-ToWslPath $archiveWin
$repoWsl = Convert-ToWslPath $Root
$installScriptWsl = "$repoWsl/scripts/install_wsl.sh"
$portArg = if ($Port) { "--port $Port" } else { "" }

Write-Host "[install] Running in WSL (sudo required) ..."
Write-Host "  sudo bash $installScriptWsl $archiveWsl --install-dir $InstallDir -y $portArg"
Write-Host ""

Invoke-Wsl "sudo bash '$installScriptWsl' '$archiveWsl' --install-dir '$InstallDir' -y $portArg"

Write-Host ""
Write-Host "Done. Open http://localhost:<port> from Windows (default port 3000 if new install)."
