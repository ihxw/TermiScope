# Build TermiScope linux/amd64 offline package (Windows host).
# Frontend: local npm, or WSL npm when Windows npm is missing. Backend: local Go or WSL Go.
#
# Usage:
#   .\scripts\build_linux_amd64.ps1           # always rebuild web/dist, then backend
#   .\scripts\build_linux_amd64.ps1 -SkipWeb  # skip frontend (must already have web/dist)
#   .\scripts\build_linux_amd64.ps1 -GoPath "C:\Program Files\Go\bin\go.exe"
#   .\scripts\build_linux_amd64.ps1 -UseWslGo          # backend via WSL Go
#   .\scripts\build_linux_amd64.ps1 -NoWslFallback     # do not auto-use WSL when Windows Go missing

param(
    [switch]$SkipWeb,
    [switch]$UseWslGo,
    [switch]$NoWslFallback,
    [string]$GoPath = "",
    [string]$NpmPath = ""
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $Root

# Reload PATH (Go/Node/nvm installers often require a new shell).
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path", "User")

function Initialize-NvmPath {
    $nvmHome = if ($env:NVM_HOME) { $env:NVM_HOME } else { Join-Path $env:LOCALAPPDATA "nvm" }
    if (-not (Test-Path -LiteralPath $nvmHome)) { return }

    $symlink = $env:NVM_SYMLINK
    if (-not $symlink) {
        $settings = Join-Path $nvmHome "settings.txt"
        if (Test-Path -LiteralPath $settings) {
            foreach ($line in Get-Content -LiteralPath $settings) {
                if ($line -match '^\s*path:\s*(.+)\s*$') {
                    $symlink = $Matches[1].Trim()
                    break
                }
            }
        }
    }

    if ($symlink -and (Test-Path -LiteralPath (Join-Path $symlink "npm.cmd"))) {
        if ($env:Path -notlike "*$symlink*") {
            $env:Path = "$symlink;$env:Path"
        }
        Write-Host "[build] nvm: $symlink"
        return
    }

    $versions = Get-ChildItem -LiteralPath $nvmHome -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^v\d' } |
        Sort-Object {
            try { [version]($_.Name -replace '^v', '') } catch { [version]'0.0.0' }
        } -Descending

    foreach ($ver in $versions) {
        $npmCmd = Join-Path $ver.FullName "npm.cmd"
        if (Test-Path -LiteralPath $npmCmd) {
            if ($env:Path -notlike "*$($ver.FullName)*") {
                $env:Path = "$($ver.FullName);$env:Path"
            }
            Write-Host "[build] nvm: $($ver.FullName)"
            return
        }
    }
}

Initialize-NvmPath

function Convert-ToWslPath([string]$WindowsPath) {
    if (Test-Path -LiteralPath $WindowsPath) {
        $resolved = (Resolve-Path -LiteralPath $WindowsPath).Path
    } else {
        $parent = Split-Path -Parent $WindowsPath
        $leaf = Split-Path -Leaf $WindowsPath
        if ($parent -and (Test-Path -LiteralPath $parent)) {
            $resolved = Join-Path (Resolve-Path -LiteralPath $parent).Path $leaf
        } else {
            $resolved = [System.IO.Path]::GetFullPath($WindowsPath)
        }
    }
    if ($resolved -match '^([A-Za-z]):\\(.*)$') {
        $drive = $Matches[1].ToLower()
        $rest = $Matches[2] -replace '\\', '/'
        return "/mnt/$drive/$rest"
    }
    return $resolved -replace '\\', '/'
}

function Get-GoInstallPathFromRegistry {
    foreach ($key in @("HKLM:\SOFTWARE\Go", "HKLM:\SOFTWARE\WOW6432Node\Go")) {
        try {
            $install = (Get-ItemProperty -Path $key -ErrorAction Stop).InstallPath
            if ($install) {
                $candidate = Join-Path $install "bin\go.exe"
                if (Test-Path $candidate) { return $candidate }
            }
        } catch { }
    }
    return $null
}

function Find-Tool {
    param(
        [string]$Name,
        [string]$ManualPath,
        [string[]]$ExtraPaths
    )
    if ($ManualPath) {
        if (Test-Path $ManualPath) { return (Resolve-Path $ManualPath).Path }
        throw "Path not found for ${Name}: $ManualPath"
    }

    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    foreach ($p in $ExtraPaths) {
        if ($p -and (Test-Path $p)) { return (Resolve-Path $p).Path }
    }
    return $null
}

function Test-DistReady {
    param([string]$DistDir)
    return (Test-Path $DistDir) -and ((Get-ChildItem $DistDir -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0)
}

function Test-WslNpmAvailable {
    if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) { return $false }
    wsl bash -c 'test -x "$HOME/.local/termiscope-build-tools/node/bin/npm" || command -v npm >/dev/null' 2>$null | Out-Null
    return $LASTEXITCODE -eq 0
}

function Invoke-WslWebBuild {
    param([string]$SrcRoot)
    $wslSrc = Convert-ToWslPath $SrcRoot
    $scriptPath = Join-Path $env:TEMP "termiscope-wsl-web-build.sh"
    $content = @"
#!/usr/bin/env bash
set -euo pipefail
WORK="`$HOME/termiscope-build-work"
SRC='$wslSrc'
mkdir -p "`$WORK"
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete --exclude release --exclude .git --exclude web/node_modules --exclude data "`$SRC/" "`$WORK/"
else
  rm -rf "`$WORK"/*
  tar -C "`$SRC" --exclude=release --exclude=.git --exclude=web/node_modules --exclude=data -cf - . | tar -C "`$WORK" -xf -
fi
export PATH="`$HOME/.local/termiscope-build-tools/node/bin:`$PATH"
NPM="`$HOME/.local/termiscope-build-tools/node/bin/npm"
if [ ! -x "`$NPM" ]; then NPM="`$(command -v npm)"; fi
if [ ! -x "`$NPM" ]; then echo "npm not found in WSL" >&2; exit 127; fi
cd "`$WORK/web"
"`$NPM" install --no-audit --no-fund
"`$NPM" run build
mkdir -p "`$SRC/web/dist"
rsync -a "`$WORK/web/dist/" "`$SRC/web/dist/"
"@
    $content = $content -replace "`r`n", "`n"
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($scriptPath, $content, $utf8NoBom)
    $scriptWsl = Convert-ToWslPath $scriptPath
    Write-Host "[build] WSL npm frontend build (linux filesystem work tree)..."
    try {
        wsl bash $scriptWsl
        if ($LASTEXITCODE -ne 0) { throw "WSL frontend build failed (exit $LASTEXITCODE)" }
    } finally {
        Remove-Item -Force $scriptPath -ErrorAction SilentlyContinue
    }
}

function New-WslBuildScript {
    param(
        [string]$WslRoot,
        [string]$OutWsl,
        [string]$Ldflags
    )
    $scriptPath = Join-Path $env:TEMP "termiscope-wsl-go-build.sh"
    $ld = $Ldflags -replace "'", "'\''"
    $content = @"
#!/usr/bin/env bash
set -euo pipefail
GO="`$HOME/.local/termiscope-build-tools/go/bin/go"
if [ ! -x "`$GO" ]; then
  GO="`$(command -v go 2>/dev/null || true)"
fi
if [ -z "`$GO" ] || [ ! -x "`$GO" ]; then
  echo "go not found in WSL" >&2
  exit 127
fi
cd '$WslRoot'
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 "`$GO" build -ldflags '$ld' -o '$OutWsl' ./cmd/server
"@
    $content = $content -replace "`r`n", "`n"
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($scriptPath, $content, $utf8NoBom)
    return $scriptPath
}

function Test-WslGoAvailable {
    if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) { return $false }
    wsl bash -c 'test -x "$HOME/.local/termiscope-build-tools/go/bin/go" && "$HOME/.local/termiscope-build-tools/go/bin/go" version' 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { return $true }
    wsl bash -c 'command -v go >/dev/null && go version' 2>$null | Out-Null
    return $LASTEXITCODE -eq 0
}

function Invoke-WslGoBuild {
    param(
        [string]$Ldflags,
        [string]$BinaryOut
    )
    $wslRoot = Convert-ToWslPath $Root
    $outWsl = Convert-ToWslPath $BinaryOut
    $scriptWin = New-WslBuildScript -WslRoot $wslRoot -OutWsl $outWsl -Ldflags $Ldflags
    $scriptWsl = Convert-ToWslPath $scriptWin
    Write-Host "[build] WSL Go cross-compile..."
    try {
        wsl bash $scriptWsl
        if ($LASTEXITCODE -ne 0) { throw "WSL go build failed (exit $LASTEXITCODE)" }
    } finally {
        Remove-Item -Force $scriptWin -ErrorAction SilentlyContinue
    }
}

$Go = Find-Tool "go" $GoPath @(
    (Get-GoInstallPathFromRegistry)
    "$env:ProgramFiles\Go\bin\go.exe"
    "${env:ProgramFiles(x86)}\Go\bin\go.exe"
    "$env:LOCALAPPDATA\Programs\Go\bin\go.exe"
    "C:\Go\bin\go.exe"
)
$UseWslForGo = $false

if (-not $Go) {
    if ($UseWslGo -or ((-not $NoWslFallback) -and (Test-WslGoAvailable))) {
        $UseWslForGo = $true
        Write-Host "[build] Windows Go not found; using WSL Go for backend cross-compile."
        Write-Host "[build] (Install Windows Go: winget install GoLang.Go — or pass -NoWslFallback to disable this fallback)"
    } else {
        throw @"
Go not found on Windows.

Install Go and reopen PowerShell:
  winget install GoLang.Go

Or specify an existing install:
  .\scripts\build_linux_amd64.ps1 -GoPath "C:\Program Files\Go\bin\go.exe"

Or use WSL Go for backend only:
  .\scripts\build_linux_amd64.ps1 -UseWslGo

Or build entirely in WSL:
  wsl bash scripts/build_linux_amd64.sh
"@
    }
}

$nvmNpmCandidates = @()
if ($env:NVM_SYMLINK) { $nvmNpmCandidates += (Join-Path $env:NVM_SYMLINK "npm.cmd") }
$nvmHome = if ($env:NVM_HOME) { $env:NVM_HOME } else { Join-Path $env:LOCALAPPDATA "nvm" }
if (Test-Path -LiteralPath $nvmHome) {
    Get-ChildItem -LiteralPath $nvmHome -Directory -Filter "v*" -ErrorAction SilentlyContinue |
        ForEach-Object { $nvmNpmCandidates += (Join-Path $_.FullName "npm.cmd") }
}

$Npm = Find-Tool "npm" $NpmPath @(
    $nvmNpmCandidates
    "$env:ProgramFiles\nodejs\npm.cmd"
    "$env:LOCALAPPDATA\Programs\nodejs\npm.cmd"
    "$env:APPDATA\npm\npm.cmd"
)

$pkg = Get-Content (Join-Path $Root "web\package.json") -Raw | ConvertFrom-Json
$Version = $pkg.version
$OutName = "termiscope-linux-amd64-$Version"
$ReleaseRoot = Join-Path $Root "release"
$OutDir = Join-Path $ReleaseRoot $OutName
$Archive = Join-Path $ReleaseRoot "$OutName.tar.gz"
$DistDir = Join-Path $Root "web\dist"
$UseWslForNpm = $false

Write-Host "[build] TermiScope $Version linux/amd64"
if ($UseWslForGo) {
    Write-Host "[build] Backend: WSL Go (linux/amd64)"
} else {
    Write-Host "[build] Go:  $Go"
    & $Go version
}

if ($SkipWeb) {
    if (-not (Test-DistReady $DistDir)) {
        throw "web/dist is missing or empty. Omit -SkipWeb to build the frontend."
    }
    Write-Host "[build] 1/3 Skipping frontend (-SkipWeb)"
} else {
    if (-not $Npm) {
        if (Test-WslNpmAvailable) {
            $UseWslForNpm = $true
            Write-Host "[build] Windows npm not found; using WSL npm for frontend."
        } else {
            throw @"
npm not found on Windows or WSL.

nvm: activate a version then reopen PowerShell:
  nvm install lts
  nvm use lts

Or pass npm path:
  .\scripts\build_linux_amd64.ps1 -NpmPath "$env:LOCALAPPDATA\nvm\v24.15.0\npm.cmd"
"@
        }
    }
    Write-Host "[build] 1/3 Building frontend (always rebuild web/dist)..."
    if ($UseWslForNpm) {
        Invoke-WslWebBuild -SrcRoot $Root
    } else {
        Write-Host "[build] npm: $Npm"
        Push-Location (Join-Path $Root "web")
        try {
            & $Npm install --no-audit --no-fund
            if ($LASTEXITCODE -ne 0) { throw "npm install failed (exit $LASTEXITCODE)" }
            & $Npm run build
            if ($LASTEXITCODE -ne 0) { throw "npm run build failed (exit $LASTEXITCODE)" }
        } finally {
            Pop-Location
        }
    }
}

if (-not (Test-DistReady $DistDir)) {
    throw "web/dist is missing after frontend step."
}

Write-Host "[build] 2/3 Building backend (CGO_ENABLED=0 GOOS=linux GOARCH=amd64)..."
if (Test-Path $OutDir) { Remove-Item -Recurse -Force $OutDir }
$null = New-Item -ItemType Directory -Force -Path @(
    $OutDir,
    (Join-Path $OutDir "web"),
    (Join-Path $OutDir "configs"),
    (Join-Path $OutDir "data"),
    (Join-Path $OutDir "logs"),
    (Join-Path $OutDir "agents"),
    (Join-Path $OutDir "scripts")
)

$Ldflags = "-s -w -X github.com/ihxw/termiscope/internal/config.Version=$Version"
$BinaryOut = Join-Path $OutDir "TermiScope"

if ($UseWslForGo) {
    Invoke-WslGoBuild -Ldflags $Ldflags -BinaryOut $BinaryOut
} else {
    $env:CGO_ENABLED = "0"
    $env:GOOS = "linux"
    $env:GOARCH = "amd64"
    & $Go build -ldflags $Ldflags -o $BinaryOut ./cmd/server
    if ($LASTEXITCODE -ne 0) { throw "go build failed (exit $LASTEXITCODE)" }
}

if (-not (Test-Path $BinaryOut)) {
    throw "Binary not produced: $BinaryOut"
}

Write-Host "[build] 3/3 Packaging..."
Copy-Item -Recurse -Force $DistDir (Join-Path $OutDir "web\dist")
Copy-Item (Join-Path $Root "configs\config.example.yaml") (Join-Path $OutDir "configs\config.yaml.example")

$InstallScripts = @(
    "install_local.sh",
    "install_from_archive.sh",
    "install_wsl.sh",
    "uninstall.sh",
    "repair_database.sh"
)
foreach ($script in $InstallScripts) {
    Copy-Item (Join-Path $Root "scripts\$script") (Join-Path $OutDir "scripts\")
}

@"
TermiScope $Version — Linux amd64 offline package

Built with scripts/build_linux_amd64.ps1 on Windows.

WSL install (this machine):
  powershell -File scripts/build_and_install_wsl.ps1

WSL / Linux (from archive):
  sudo bash scripts/install_wsl.sh /path/to/$OutName.tar.gz -y

Target server:
  tar -xzf $OutName.tar.gz && cd $OutName && sudo ./scripts/install_local.sh -y
"@ | Set-Content -Encoding UTF8 (Join-Path $OutDir "INSTALL.txt")

Write-Host "[build] Creating archive..."
$null = New-Item -ItemType Directory -Force -Path $ReleaseRoot
if (Test-Path $Archive) { Remove-Item -Force $Archive }

$tar = Get-Command tar -ErrorAction SilentlyContinue
if (-not $tar) {
    throw "tar not found. Windows 10+ includes tar; enable or install bsdtar."
}
& $tar.Source -czf $Archive -C $ReleaseRoot $OutName
if ($LASTEXITCODE -ne 0) { throw "tar failed (exit $LASTEXITCODE)" }

Write-Host ""
Write-Host "[build] Done:"
Write-Host "  Folder:  $OutDir"
Write-Host "  Archive: $Archive"
Get-Item $Archive, $BinaryOut | Format-Table Name, @{ N = "Size(MB)"; E = { [math]::Round($_.Length / 1MB, 2) } }, LastWriteTime -AutoSize
