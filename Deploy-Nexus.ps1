# Deploy-Nexus.ps1
# Provisions Nexus as an Azure Container App from GHCR with persistent file shares.
# Run once to set up the environment, then use Update-Nexus.ps1 for image updates.
#
# Prerequisites:
#   - Azure CLI installed (az) with the containerapp extension
#   - Logged in: az login
#   - A Service Principal created (see Deploy-to-ACA.md, Prerequisite A)
#   - A NEXUS_CREDENTIAL_KEY generated (see Deploy-to-ACA.md, Prerequisite B)

param(
    [Parameter(Mandatory)]
    [string]$ResourceGroup,

    [Parameter(Mandatory)]
    [string]$Location,

    [Parameter(Mandatory)]
    [string]$AzureClientId,

    [Parameter(Mandatory)]
    [string]$AzureClientSecret,

    [Parameter(Mandatory)]
    [string]$AzureTenantId,

    [Parameter(Mandatory)]
    [string]$NexusCredentialKey,

    [string]$AppName = 'nexus-app',
    [string]$EnvironmentName = 'nexus-env',
    [string]$StorageAccountName
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Step { param([string]$Message) Write-Host "`n>>> $Message" -ForegroundColor Cyan }

# ---------- defaults ----------
if (-not $StorageAccountName) {
    $suffix = (Get-Random -Maximum 99999).ToString('00000')
    $StorageAccountName = "nexusfiles$suffix"
}

$Image = 'ghcr.io/jayarep/nexus:latest'

Write-Host "============================================" -ForegroundColor Yellow
Write-Host "  Nexus - Azure Container App Deployment"    -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Resource Group:    $ResourceGroup"
Write-Host "  Location:          $Location"
Write-Host "  Container App:     $AppName"
Write-Host "  Environment:       $EnvironmentName"
Write-Host "  Storage Account:   $StorageAccountName"
Write-Host "  Image:             $Image"
Write-Host ""

# ---------- 1. Resource Group ----------
Write-Step "Creating Resource Group '$ResourceGroup'..."
az group create --name $ResourceGroup --location $Location --output none

# ---------- 2. Container Apps Environment ----------
Write-Step "Creating Container Apps Environment '$EnvironmentName'..."
az containerapp env create --resource-group $ResourceGroup --name $EnvironmentName --location $Location --output none

# ---------- 3. Storage Account & File Shares ----------
Write-Step "Creating Storage Account '$StorageAccountName' and file shares..."
az storage account create --resource-group $ResourceGroup --name $StorageAccountName --location $Location --sku Standard_LRS --kind StorageV2 --output none

$storageKey = (az storage account keys list --resource-group $ResourceGroup --account-name $StorageAccountName --query '[0].value' -o tsv)

foreach ($shareName in @('nexus-conf', 'ps-modules', 'py-packages')) {
    az storage share create --name $shareName --account-name $StorageAccountName --account-key $storageKey --output none
    Write-Host "  Created file share: $shareName"
}

# ---------- 4. Link storage to environment ----------
Write-Step "Linking file shares to environment..."

$storageLinks = @(
    @{ Name = 'nexusconf';       Share = 'nexus-conf' }
    @{ Name = 'nexuspsmodules';  Share = 'ps-modules' }
    @{ Name = 'nexuspypackages'; Share = 'py-packages' }
)

foreach ($link in $storageLinks) {
    az containerapp env storage set --resource-group $ResourceGroup --name $EnvironmentName --storage-name $link.Name --azure-file-account-name $StorageAccountName --azure-file-account-key $storageKey --azure-file-share-name $link.Share --access-mode ReadWrite --output none
    Write-Host "  Linked: $($link.Share) -> $($link.Name)"
}

# ---------- 5. Create Container App ----------
Write-Step "Creating Container App '$AppName'..."

az containerapp create -n $AppName -g $ResourceGroup --environment $EnvironmentName --image $Image --target-port 8080 --ingress external --cpu 1.0 --memory 2Gi --min-replicas 1 --max-replicas 1 --secrets azure-client-id="$AzureClientId" azure-client-secret="$AzureClientSecret" azure-tenant-id="$AzureTenantId" nexus-credential-key="$NexusCredentialKey" --env-vars POWERSHELL_TELEMETRY_OPTOUT="1" AZURE_CLIENT_ID=secretref:azure-client-id AZURE_CLIENT_SECRET=secretref:azure-client-secret AZURE_TENANT_ID=secretref:azure-tenant-id NEXUS_CREDENTIAL_KEY=secretref:nexus-credential-key --output none

# ---------- 6. Attach volume mounts via ARM API ----------
Write-Step "Attaching volume mounts..."

$subId = az account show --query id -o tsv
$apiUrl = "https://management.azure.com/subscriptions/$subId/resourceGroups/$ResourceGroup/providers/Microsoft.App/containerApps/${AppName}?api-version=2024-03-01"

$patchBody = @{
    properties = @{
        template = @{
            containers = @(
                @{
                    name = $AppName
                    image = $Image
                    resources = @{ cpu = 1; memory = '2Gi' }
                    env = @(
                        @{ name = 'POWERSHELL_TELEMETRY_OPTOUT'; value = '1' }
                        @{ name = 'AZURE_CLIENT_ID'; secretRef = 'azure-client-id' }
                        @{ name = 'AZURE_CLIENT_SECRET'; secretRef = 'azure-client-secret' }
                        @{ name = 'AZURE_TENANT_ID'; secretRef = 'azure-tenant-id' }
                        @{ name = 'NEXUS_CREDENTIAL_KEY'; secretRef = 'nexus-credential-key' }
                    )
                    volumeMounts = @(
                        @{ volumeName = 'nexus-conf'; mountPath = '/app/conf' }
                        @{ volumeName = 'ps-modules'; mountPath = '/usr/local/share/powershell/Modules' }
                        @{ volumeName = 'py-packages'; mountPath = '/usr/local/lib/python3.10/dist-packages' }
                    )
                }
            )
            scale = @{ minReplicas = 1; maxReplicas = 1 }
            volumes = @(
                @{ name = 'nexus-conf'; storageName = 'nexusconf'; storageType = 'AzureFile' }
                @{ name = 'ps-modules'; storageName = 'nexuspsmodules'; storageType = 'AzureFile' }
                @{ name = 'py-packages'; storageName = 'nexuspypackages'; storageType = 'AzureFile' }
            )
        }
    }
} | ConvertTo-Json -Depth 10 -Compress

$tmpBody = Join-Path $env:TEMP 'nexus-patch.json'
$patchBody | Set-Content -Path $tmpBody -Encoding UTF8
az rest --method PATCH --url $apiUrl --body "@$tmpBody" --output none
Remove-Item $tmpBody -Force -ErrorAction SilentlyContinue

# ---------- 7. Output ----------
Write-Step "Deployment complete!"
$fqdn = az containerapp show --resource-group $ResourceGroup --name $AppName --query 'properties.configuration.ingress.fqdn' -o tsv

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Nexus is running at:"                      -ForegroundColor Green
Write-Host "  https://$fqdn"                             -ForegroundColor White
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Storage Account:   $StorageAccountName"
Write-Host "  Resource Group:    $ResourceGroup"
Write-Host ""
Write-Host "To update after a new image is pushed:" -ForegroundColor Yellow
Write-Host "  .\Update-Nexus.ps1 -ResourceGroup $ResourceGroup -AppName $AppName" -ForegroundColor Yellow
