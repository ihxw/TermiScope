cd .\web
npm install
npm run build   
cd ..

. "$PSScriptRoot\build_agents.ps1"

go run cmd/server/main.go
