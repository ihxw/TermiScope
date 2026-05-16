# Download Go + Node Linux binaries for WSL offline build (run on Windows).
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ToolsDir = Join-Path $Root ".build-tools"
$GoVersion = "1.25.5"
$NodeVersion = "20.18.1"

New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null

function Get-IfMissing($Url, $OutFile) {
    if ((Test-Path $OutFile) -and ((Get-Item $OutFile).Length -gt 0)) {
        Write-Host "OK (cached): $OutFile"
        return
    }
    Write-Host "Downloading: $Url"
    Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
}

$goTar = Join-Path $ToolsDir "go$GoVersion.linux-amd64.tar.gz"
$nodeTar = Join-Path $ToolsDir "node-v${NodeVersion}-linux-x64.tar.gz"

Get-IfMissing "https://go.dev/dl/go$GoVersion.linux-amd64.tar.gz" $goTar
Get-IfMissing "https://nodejs.org/dist/v$NodeVersion/node-v$NodeVersion-linux-x64.tar.gz" $nodeTar

Write-Host "Done. Tool archives are in: $ToolsDir"
