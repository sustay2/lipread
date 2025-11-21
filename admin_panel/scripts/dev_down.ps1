# Stops and removes the dev stack
# Usage: powershell -ExecutionPolicy Bypass -File .\scripts\dev_down.ps1
$ErrorActionPreference = "Stop"
Push-Location (Join-Path $PSScriptRoot "..")
docker compose -f .\infra\docker-compose.dev.yml down -v
Pop-Location