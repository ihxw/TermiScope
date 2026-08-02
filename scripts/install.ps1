param(
    [string]$InstallDir = "",
    [int]$Port = 3000,
    [switch]$Y,
    [switch]$NonInteractive,
    [switch]$NoStart
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$Repo = "ihxw/TermiScope"
$TaskName = "TermiScope"
$LatestUrl = "https://api.github.com/repos/$Repo/releases/latest"

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Please run PowerShell as Administrator."
    }
}

function Get-TermiscopeArchitecture {
    $arch = $env:PROCESSOR_ARCHITECTURE
    $wowArch = $env:PROCESSOR_ARCHITEW6432

    if ($arch -eq "ARM64" -or $wowArch -eq "ARM64") {
        return "arm64"
    }
    if ($arch -eq "AMD64" -or $wowArch -eq "AMD64") {
        return "amd64"
    }

    throw "Unsupported Windows architecture: $arch"
}

function New-TermiscopeSecret {
    param([int]$Length)

    $bytes = New-Object byte[] 64
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    }
    finally {
        $rng.Dispose()
    }

    $text = [Convert]::ToBase64String($bytes) -replace '[^A-Za-z0-9]', ''
    if ($text.Length -lt $Length) {
        return New-TermiscopeSecret -Length $Length
    }
    return $text.Substring(0, $Length)
}

function New-TermiscopeWebClient {
    $client = New-Object Net.WebClient
    $client.Headers.Add("User-Agent", "TermiScope-Installer")
    return $client
}

function Get-TermiscopeLocalIPs {
    $ips = @()

    if (Get-Command Get-NetIPAddress -ErrorAction SilentlyContinue) {
        $ips += Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object {
                $_.IPAddress -and
                $_.IPAddress -notlike "127.*" -and
                $_.IPAddress -notlike "169.254.*" -and
                $_.IPAddress -ne "0.0.0.0"
            } |
            ForEach-Object { $_.IPAddress }
    }

    try {
        $ips += [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) |
            Where-Object {
                $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and
                -not [System.Net.IPAddress]::IsLoopback($_) -and
                $_.ToString() -notlike "169.254.*"
            } |
            ForEach-Object { $_.ToString() }
    }
    catch {
    }

    return $ips | Sort-Object -Unique
}

function Get-TermiscopeAllowedOriginsYaml {
    param([int]$Port)

    $origins = @(
        "http://localhost:$Port",
        "http://127.0.0.1:$Port"
    )

    foreach ($ip in Get-TermiscopeLocalIPs) {
        $origins += ("http://{0}:{1}" -f $ip, $Port)
    }

    $lines = @("  allowed_origins:")
    foreach ($origin in ($origins | Sort-Object -Unique)) {
        $lines += "    - `"$origin`""
    }
    return ($lines -join "`n")
}

function Stop-TermiscopeTask {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        Write-Host "Stopping existing scheduled task..."
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }
}

function Stop-TermiscopeProcess {
    param([string]$BinaryPath)

    if (-not (Test-Path $BinaryPath)) {
        return
    }

    Get-CimInstance Win32_Process -Filter "Name = 'TermiScope.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.ExecutablePath -eq $BinaryPath } |
        ForEach-Object {
            Write-Host "Stopping existing TermiScope process: $($_.ProcessId)"
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
}

function Get-ExistingPort {
    param([string]$ConfigPath, [int]$Fallback)

    if (-not (Test-Path $ConfigPath)) {
        return $Fallback
    }

    $match = Select-String -Path $ConfigPath -Pattern '^\s*port:\s*(\d+)' | Select-Object -First 1
    if ($match) {
        return [int]$match.Matches[0].Groups[1].Value
    }
    return $Fallback
}

Assert-Administrator

if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    $programFiles = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
    $InstallDir = Join-Path $programFiles "TermiScope"
}

$isNonInteractive = $Y -or $NonInteractive
if (-not $isNonInteractive) {
    $inputDir = Read-Host "Install location [$InstallDir]"
    if (-not [string]::IsNullOrWhiteSpace($inputDir)) {
        $InstallDir = $inputDir
    }
}

$InstallDir = [IO.Path]::GetFullPath($InstallDir)
$configPath = Join-Path $InstallDir "configs\config.yaml"
$binaryPath = Join-Path $InstallDir "TermiScope.exe"

if (-not (Test-Path $configPath) -and -not $isNonInteractive) {
    $inputPort = Read-Host "Server port [$Port]"
    if (-not [string]::IsNullOrWhiteSpace($inputPort)) {
        $Port = [int]$inputPort
    }
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$tempRoot = $null
$webClient = $null

try {
    $arch = Get-TermiscopeArchitecture
    Write-Host "Detected System: windows/$arch"

    Write-Host "Fetching latest version info..."
    $webClient = New-TermiscopeWebClient
    $release = $webClient.DownloadString($LatestUrl) | ConvertFrom-Json
    $asset = $release.assets |
        Where-Object { $_.name -match "windows-$arch\.zip$" } |
        Select-Object -First 1

    if (-not $asset) {
        throw "Could not find a release asset for windows-$arch."
    }

    Write-Host "Latest Version: $($release.tag_name)"

    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("termiscope-install-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    $assetName = [string]$asset.name
    $downloadUrl = [string]$asset.browser_download_url
    $zipPath = Join-Path $tempRoot $assetName

    Write-Host "Downloading from $downloadUrl ..."
    $webClient.DownloadFile($downloadUrl, $zipPath)

    Write-Host "Extracting..."
    Expand-Archive -Path $zipPath -DestinationPath $tempRoot -Force

    $downloadedBinary = Get-ChildItem -Path $tempRoot -Filter "TermiScope.exe" -File -Recurse |
        Select-Object -First 1
    if (-not $downloadedBinary) {
        throw "TermiScope.exe not found in downloaded package."
    }
    $packageRoot = Split-Path $downloadedBinary.FullName -Parent

    Write-Host "Installing to: $InstallDir"
    Stop-TermiscopeTask
    Stop-TermiscopeProcess -BinaryPath $binaryPath

    foreach ($dir in @(
        $InstallDir,
        (Join-Path $InstallDir "configs"),
        (Join-Path $InstallDir "data"),
        (Join-Path $InstallDir "logs"),
        (Join-Path $InstallDir "agents"),
        (Join-Path $InstallDir "web")
    )) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    Copy-Item -Path $downloadedBinary.FullName -Destination $binaryPath -Force

    $webSrc = Join-Path $packageRoot "web\dist"
    if (-not (Test-Path $webSrc)) {
        throw "web/dist not found in downloaded package."
    }
    $webDest = Join-Path $InstallDir "web\dist"
    if (Test-Path $webDest) {
        Remove-Item -Recurse -Force $webDest
    }
    Copy-Item -Path $webSrc -Destination (Join-Path $InstallDir "web") -Recurse -Force

    $agentsSrc = Join-Path $packageRoot "agents"
    if (Test-Path $agentsSrc) {
        Copy-Item -Path (Join-Path $agentsSrc "*") -Destination (Join-Path $InstallDir "agents") -Recurse -Force -ErrorAction SilentlyContinue
    }

    $scriptsSrc = Join-Path $packageRoot "scripts"
    if (Test-Path $scriptsSrc) {
        $scriptsDest = Join-Path $InstallDir "scripts"
        New-Item -ItemType Directory -Path $scriptsDest -Force | Out-Null
        Copy-Item -Path (Join-Path $scriptsSrc "*") -Destination $scriptsDest -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path $configPath) {
        $Port = Get-ExistingPort -ConfigPath $configPath -Fallback $Port
        Write-Host "Preserving existing config: $configPath"
    }
    else {
        $jwtSecret = New-TermiscopeSecret -Length 32
        $encryptionKey = New-TermiscopeSecret -Length 32
        $allowedOriginsYaml = Get-TermiscopeAllowedOriginsYaml -Port $Port

        $config = @"
server:
  port: $Port
  mode: release
$allowedOriginsYaml
  max_upload_size: 1048576000

database:
  path: ./data/termiscope.db

security:
  jwt_secret: "$jwtSecret"
  encryption_key: "$encryptionKey"
  smtp_tls_skip_verify: false

log:
  level: info
  file: ./logs/app.log
"@
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($configPath, $config, $utf8NoBom)
        Write-Host "Created $configPath"
    }

    Write-Host "Registering startup task..."
    $action = New-ScheduledTaskAction -Execute $binaryPath -WorkingDirectory $InstallDir
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 1) `
        -ExecutionTimeLimit (New-TimeSpan -Seconds 0)

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Description "TermiScope Server" `
        -Force | Out-Null

    if (-not $NoStart) {
        Write-Host "Starting TermiScope..."
        Start-ScheduledTask -TaskName $TaskName
        Start-Sleep -Seconds 2
    }

    Write-Host "=== Installation Complete ==="
    Write-Host "Dashboard: http://<your-ip>:$Port"
    Write-Host "Config: $configPath"
    Write-Host "Task: $TaskName"
}
finally {
    if ($webClient) {
        $webClient.Dispose()
    }
    if ($tempRoot -and (Test-Path $tempRoot)) {
        Remove-Item -Recurse -Force $tempRoot -ErrorAction SilentlyContinue
    }
}
