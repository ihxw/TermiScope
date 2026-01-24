
Write-Host "Cleaning up old processes..."
Stop-Process -Name "main" -ErrorAction SilentlyContinue
Stop-Process -Name "server" -ErrorAction SilentlyContinue

Write-Host "Building Server..."
go build -o server.exe .\cmd\server\main.go
if ($LastExitCode -ne 0) {
    Write-Error "Build failed!"
    exit 1
}

Write-Host "Starting Server..."
.\server.exe
