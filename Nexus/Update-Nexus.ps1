# Update-Nexus.ps1
# Rebuilds the Docker image and updates the Azure Container App
# Use after making local code changes to push updates to Azure
#
# Prerequisites:
#   - Azure CLI installed (az)
#   - Logged in: az login
#   - Nexus already deployed via Deploy-Nexus.ps1

param(
    [Parameter(Mandatory)]
    [string]$ResourceGroup,

    [Parameter(Mandatory)]
    [string]$RegistryName,

    [string]$AppName = 'nexus-app'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Step { param([string]$Message) Write-Host "`n>>> $Message" -ForegroundColor Cyan }

$imageName = "$($RegistryName).azurecr.io/nexus"

# ---------- 1. Stamp version ----------
$version = Get-Date -Format 'yyyyMMdd-HHmmss'
$version | Set-Content -Path (Join-Path $PSScriptRoot 'version.txt') -NoNewline
Write-Host "Version: $version" -ForegroundColor Yellow

# ---------- 2. Build & push image via ACR ----------
Write-Step "Building image in ACR '$RegistryName'..."
az acr build --registry $RegistryName --image "nexus:$version" --image "nexus:latest" --file ./Dockerfile . --no-logs --output none

# ---------- 3. Update Container App ----------
Write-Step "Updating Container App '$AppName'..."
az containerapp update `
    --resource-group $ResourceGroup `
    --name $AppName `
    --image "${imageName}:${version}" `
    --output none

# ---------- 4. Verify ----------
Write-Step "Update complete!"
$fqdn = az containerapp show --resource-group $ResourceGroup --name $AppName --query 'properties.configuration.ingress.fqdn' -o tsv

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Nexus updated to version: $version" -ForegroundColor Green
Write-Host "  https://$fqdn" -ForegroundColor White
Write-Host "============================================" -ForegroundColor Green
