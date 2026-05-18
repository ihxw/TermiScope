# Build TermiScope linux/amd64 offline package on Windows (cross-compile).
# Requires: Go (https://go.dev/dl/), Node.js/npm for frontend (or existing web/dist).
# Usage:  .\scripts\build_linux_amd64.ps1
#         .\scripts\build_linux_amd64.ps1 -SkipWeb

param(
    [switch]$SkipWeb,
    [switch]$RebuildWeb
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $Root

function Find-Go {
    $list = @()
    $cmd = Get-Command go -ErrorAction SilentlyContinue
    if ($cmd) { $list += $cmd.Source }
    $list += @(
        "$env:ProgramFiles\Go\bin\go.exe"
        "${env:ProgramFiles(x86)}\Go\bin\go.exe"
        "$env:LOCALAPPDATA\Programs\Go\bin\go.exe"
    )
    foreach ($p in $list) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    throw "Go not found. Install from https://go.dev/dl/ and ensure go is on PATH."
}

function Find-Npm {
    $list = @()
    $cmd = Get-Command npm -ErrorAction SilentlyContinue
    if ($cmd) { $list += $cmd.Source }
    $list += @(
        "$env:ProgramFiles\nodejs\npm.cmd"
        "$env:LOCALAPPDATA\Programs\nodejs\npm.cmd"
    )
    foreach ($p in $list) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    return $null
}

$pkg = Get-Content (Join-Path $Root "web\package.json") -Raw | ConvertFrom-Json
$Version = $pkg.version
$OutName = "termiscope-linux-amd64-$Version"
$ReleaseRoot = Join-Path $Root "release"
$OutDir = Join-Path $ReleaseRoot $OutName
$Archive = Join-Path $ReleaseRoot "$OutName.tar.gz"

$go = $null
try { $go = Find-Go } catch { Write-Host "[build] $_" }

Write-Host "[build] TermiScope $Version linux/amd64"

$distDir = Join-Path $Root "web\dist"
$hasDist = (Test-Path $distDir) -and ((Get-ChildItem $distDir -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0)

if (-not $SkipWeb -and ($RebuildWeb -or -not $hasDist)) {
    $npm = Find-Npm
    if (-not $npm) { throw "npm not found. Install Node.js or build web/dist manually, then use -SkipWeb." }
    Write-Host "[build] Building frontend..."
    Push-Location (Join-Path $Root "web")
    try {
        & $npm install --no-audit --no-fund
        if ($LASTEXITCODE -ne 0) { throw "npm install failed" }
        & $npm run build
        if ($LASTEXITCODE -ne 0) { throw "npm run build failed" }
    } finally {
        Pop-Location
    }
} elseif (-not $hasDist) {
    $releaseDist = Get-ChildItem (Join-Path $Root "release\termiscope-linux-amd64-*\web\dist") -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($releaseDist) {
        Write-Host "[build] Using web/dist from previous release: $($releaseDist.FullName)"
        $null = New-Item -ItemType Directory -Force -Path $distDir
        Copy-Item -Recurse -Force (Join-Path $releaseDist.FullName "*") $distDir
    } else {
        Write-Host "[build] web/dist missing on Windows; trying WSL build ..."
        $wslRoot = Convert-ToWslPath $Root
        $skipFlag = if ($SkipWeb) { "--skip-web" } else { "" }
        wsl bash -lc "cd '$wslRoot' && bash scripts/build_linux_amd64.sh $skipFlag"
        if ($LASTEXITCODE -ne 0) { throw "WSL build failed" }
        Write-Host "[build] WSL build finished."
        return
    }
} else {
    Write-Host "[build] Using existing web/dist"
}

Write-Host "[build] Building backend..."
if (Test-Path $OutDir) { Remove-Item -Recurse -Force $OutDir }
$null = New-Item -ItemType Directory -Force -Path @(
    $OutDir,
    (Join-Path $OutDir "web"),
    (Join-Path $OutDir "configs"),
    (Join-Path $OutDir "scripts"),
    (Join-Path $OutDir "agents")
)

$ldflags = "-s -w -X github.com/ihxw/termiscope/internal/config.Version=$Version"
$binaryOut = Join-Path $OutDir "TermiScope"
function Convert-ToWslPath([string]$WindowsPath) {
    $p = $WindowsPath -replace '\\', '/'
    if ($p -match '^([A-Za-z]):/(.*)$') {
        return "/mnt/$($Matches[1].ToLower())/$($Matches[2])"
    }
    return $p
}

$wslRoot = Convert-ToWslPath $Root

if ($go) {
    Write-Host "[build] Go: $go"
    & $go version
    $env:CGO_ENABLED = "0"
    $env:GOOS = "linux"
    $env:GOARCH = "amd64"
    & $go build -ldflags $ldflags -o $binaryOut ./cmd/server
    if ($LASTEXITCODE -ne 0) { throw "go build failed" }
} else {
    Write-Host "[build] Windows Go not found; cross-compiling via WSL ..."
    $outWsl = Convert-ToWslPath $binaryOut
    $wslCmd = "export PATH=`$HOME/.local/termiscope-build-tools/go/bin:`$PATH; cd '$wslRoot' && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags '$ldflags' -o '$outWsl' ./cmd/server"
    wsl bash -lc $wslCmd
    if ($LASTEXITCODE -ne 0) { throw "WSL go build failed" }
}

Copy-Item -Recurse -Force (Join-Path $Root "web\dist") (Join-Path $OutDir "web\dist")
Copy-Item (Join-Path $Root "configs\config.yaml") (Join-Path $OutDir "configs\config.yaml.example")
Copy-Item (Join-Path $Root "scripts\install_local.sh") (Join-Path $OutDir "scripts\")
Copy-Item (Join-Path $Root "scripts\install_from_archive.sh") (Join-Path $OutDir "scripts\")
Copy-Item (Join-Path $Root "scripts\install_wsl.sh") (Join-Path $OutDir "scripts\")
Copy-Item (Join-Path $Root "scripts\uninstall.sh") (Join-Path $OutDir "scripts\")
Copy-Item (Join-Path $Root "scripts\repair_database.sh") (Join-Path $OutDir "scripts\")

@"
TermiScope $Version — Linux amd64 offline package

On WSL (after Windows build):
  powershell -File scripts/build_and_install_wsl.ps1

Or in WSL only:
  sudo bash scripts/install_wsl.sh /path/to/$OutName.tar.gz -y

On target server:
  sudo bash scripts/install_from_archive.sh /path/to/$OutName.tar.gz

Or extract and install:
  tar -xzf $OutName.tar.gz
  cd $OutName
  sudo ./scripts/install_local.sh -y

Existing config and database under the install dir are never overwritten.
"@ | Set-Content -Encoding UTF8 (Join-Path $OutDir "INSTALL.txt")

Write-Host "[build] Creating archive..."
$null = New-Item -ItemType Directory -Force -Path $ReleaseRoot
if (Test-Path $Archive) { Remove-Item -Force $Archive }
tar -czf $Archive -C $ReleaseRoot $OutName

Write-Host "[build] Done:"
Write-Host "  Folder:  $OutDir"
Write-Host "  Archive: $Archive"
Get-Item $Archive, $binaryOut | Format-Table Name, Length, LastWriteTime
