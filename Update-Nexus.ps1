# Update-Nexus.ps1
# Pulls the latest image from GHCR and updates the Azure Container App.
# Use after publishContainer.ps1 has pushed a new image.
#
# Prerequisites:
#   - Azure CLI installed (az)
#   - Logged in: az login
#   - Nexus already deployed via Deploy-Nexus.ps1

param(
    [Parameter(Mandatory)]
    [string]$ResourceGroup,

    [string]$AppName = 'nexus-app'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Step { param([string]$Message) Write-Host "`n>>> $Message" -ForegroundColor Cyan }

$Image = 'ghcr.io/jayarep/nexus:latest'

# ---------- 1. Update Container App ----------
Write-Step "Updating Container App '$AppName' to latest image..."
az containerapp update --resource-group $ResourceGroup --name $AppName --image $Image --output none

# ---------- 2. Verify ----------
Write-Step "Update complete!"
$fqdn = az containerapp show --resource-group $ResourceGroup --name $AppName --query 'properties.configuration.ingress.fqdn' -o tsv
$revision = az containerapp show --resource-group $ResourceGroup --name $AppName --query 'properties.latestRevisionName' -o tsv

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Nexus updated"                             -ForegroundColor Green
Write-Host "  Revision: $revision"                       -ForegroundColor Green
Write-Host "  https://$fqdn"                             -ForegroundColor White
Write-Host "============================================" -ForegroundColor Green
