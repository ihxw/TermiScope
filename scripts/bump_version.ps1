Param()
$ErrorActionPreference = 'Stop'
$pkg = 'web/package.json'
if (-not (Test-Path $pkg)) { Write-Error "Package file not found: $pkg"; exit 1 }

# Avoid recursion: if last commit is bump, skip
$last = git log -1 --pretty=%B 2>$null
if ($last -like 'Bump version to*') { Write-Host 'Last commit is a version bump, skipping.'; exit 0 }

$json = Get-Content $pkg -Raw | ConvertFrom-Json
if (-not $json.version) { Write-Error 'version not found in package.json'; exit 1 }
$parts = $json.version -split '\.'
[int]$major = $parts[0]
[int]$minor = $parts[1]
[int]$patch = $parts[2]
$patch++
$new = "$major.$minor.$patch"
$json.version = $new
# Write back nicely
$json | ConvertTo-Json -Depth 10 | Set-Content $pkg

git add $pkg
if ((git diff --cached --quiet) -eq $false) {
    git commit -m "Bump version to $new"
    Write-Host "Version bumped to $new"
} else {
    Write-Host "No changes to commit."
}
