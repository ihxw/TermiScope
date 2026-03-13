# TermiScope Setup Script
# This script helps you set up the required environment variables

Write-Host "==================================" -ForegroundColor Cyan
Write-Host "TermiScope Environment Setup" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Host ""

# Function to generate random string
function Get-RandomString {
    param([int]$Length)
    $bytes = New-Object byte[] $Length
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    return [Convert]::ToBase64String($bytes).Substring(0, $Length)
}

# Generate default JWT Secret (32+ characters)
$defaultJwtSecret = Get-RandomString -Length 32
Write-Host "JWT Secret Configuration" -ForegroundColor Green
Write-Host "------------------------" -ForegroundColor Gray
Write-Host "A secure random JWT secret has been generated." -ForegroundColor Yellow
Write-Host "Default value: " -NoNewline -ForegroundColor Gray
Write-Host $defaultJwtSecret -ForegroundColor Cyan
Write-Host ""
$userJwtSecret = Read-Host "Press Enter to use default, or type your own (min 32 chars)"
if ([string]::IsNullOrWhiteSpace($userJwtSecret)) {
    $jwtSecret = $defaultJwtSecret
    Write-Host "✓ Using generated JWT secret" -ForegroundColor Green
}
else {
    if ($userJwtSecret.Length -lt 32) {
        Write-Host "✗ Error: JWT secret must be at least 32 characters!" -ForegroundColor Red
        exit 1
    }
    $jwtSecret = $userJwtSecret
    Write-Host "✓ Using custom JWT secret" -ForegroundColor Green
}
Write-Host ""

# Generate default Encryption Key (exactly 32 bytes)
$defaultEncryptionKey = Get-RandomString -Length 32
Write-Host "Encryption Key Configuration" -ForegroundColor Green
Write-Host "----------------------------" -ForegroundColor Gray
Write-Host "A secure random encryption key has been generated." -ForegroundColor Yellow
Write-Host "Default value: " -NoNewline -ForegroundColor Gray
Write-Host $defaultEncryptionKey -ForegroundColor Cyan
Write-Host ""
$userEncryptionKey = Read-Host "Press Enter to use default, or type your own (exactly 32 chars)"
if ([string]::IsNullOrWhiteSpace($userEncryptionKey)) {
    $encryptionKey = $defaultEncryptionKey
    Write-Host "✓ Using generated encryption key" -ForegroundColor Green
}
else {
    if ($userEncryptionKey.Length -ne 32) {
        Write-Host "✗ Error: Encryption key must be exactly 32 characters!" -ForegroundColor Red
        exit 1
    }
    $encryptionKey = $userEncryptionKey
    Write-Host "✓ Using custom encryption key" -ForegroundColor Green
}
Write-Host ""

Write-Host "==================================" -ForegroundColor Cyan
Write-Host "Saving Configuration..." -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Host ""

# Update config.yaml if exists
$configPath = "configs\config.yaml"
if (Test-Path $configPath) {
    Write-Host "Updating $configPath..." -ForegroundColor Yellow
    
    # Read config file
    $config = Get-Content $configPath -Raw
    
    # Update JWT secret
    $config = $config -replace 'jwt_secret:\s*"[^"]*"', "jwt_secret: `"$jwtSecret`""
    
    # Update encryption key
    $config = $config -replace 'encryption_key:\s*"[^"]*"', "encryption_key: `"$encryptionKey`""
    
    # Save updated config
    $config | Set-Content $configPath -NoNewline
    
    Write-Host "✓ Configuration file updated!" -ForegroundColor Green
}
else {
    Write-Host "⚠ Config file not found at $configPath" -ForegroundColor Yellow
    Write-Host "  Please set these values manually in your config file." -ForegroundColor Gray
}
Write-Host ""

Write-Host "==================================" -ForegroundColor Cyan
Write-Host "Setting Environment Variables..." -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Host ""

# Set environment variables for current session
$env:TERMISCOPE_JWT_SECRET = $jwtSecret
$env:TERMISCOPE_ENCRYPTION_KEY = $encryptionKey

Write-Host "✓ Environment variables set for current session!" -ForegroundColor Green
Write-Host ""
Write-Host "To make these permanent, add them to your system environment variables:" -ForegroundColor Yellow
Write-Host ""
Write-Host "TERMISCOPE_JWT_SECRET=$jwtSecret" -ForegroundColor White
Write-Host "TERMISCOPE_ENCRYPTION_KEY=$encryptionKey" -ForegroundColor White
Write-Host ""
Write-Host "==================================" -ForegroundColor Cyan
Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Install frontend dependencies:" -ForegroundColor White
Write-Host "   cd web" -ForegroundColor Gray
Write-Host "   npm install" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Start the backend server:" -ForegroundColor White
Write-Host "   go run cmd/server/main.go" -ForegroundColor Gray
Write-Host ""
Write-Host "3. In another terminal, start the frontend dev server:" -ForegroundColor White
Write-Host "   cd web" -ForegroundColor Gray
Write-Host "   npm run dev" -ForegroundColor Gray
Write-Host ""
Write-Host "4. Open your browser and navigate to:" -ForegroundColor White
Write-Host "   http://localhost:5173" -ForegroundColor Gray
Write-Host ""
Write-Host "5. Login with default credentials:" -ForegroundColor White
Write-Host "   Username: admin" -ForegroundColor Gray
Write-Host "   Password: admin123" -ForegroundColor Gray
Write-Host ""
Write-Host "⚠️  IMPORTANT: Change the default password after first login!" -ForegroundColor Red
Write-Host ""
