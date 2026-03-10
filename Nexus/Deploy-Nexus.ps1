# Deploy-Nexus.ps1
# Provisions Nexus as an Azure Container App with persistent file shares
# Run once to set up the environment, then use Update-Nexus.ps1 for updates
#
# Prerequisites:
#   - Azure CLI installed (az)
#   - Logged in: az login
#   - Docker installed (for building/pushing image)

param(
    [Parameter(Mandatory)]
    [string]$ResourceGroup,

    [Parameter(Mandatory)]
    [string]$Location,

    [string]$AppName = 'nexus-app',
    [string]$EnvironmentName = 'nexus-env',
    [string]$RegistryName,          # ACR name (auto-generated if omitted)
    [string]$StorageAccountName,    # For file shares (auto-generated if omitted)
    [string]$AzureClientId = $env:AZURE_CLIENT_ID,
    [string]$AzureClientSecret = $env:AZURE_CLIENT_SECRET,
    [string]$AzureTenantId = $env:AZURE_TENANT_ID
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ---------- helpers ----------
function Write-Step { param([string]$Message) Write-Host "`n>>> $Message" -ForegroundColor Cyan }

# ---------- defaults ----------
$suffix = (Get-Random -Maximum 9999).ToString('0000')
if (-not $RegistryName)      { $RegistryName      = "nexusacr$suffix" }
if (-not $StorageAccountName) { $StorageAccountName = "nexusfiles$suffix" }
$imageName = "$($RegistryName).azurecr.io/nexus:latest"

Write-Host "============================================" -ForegroundColor Yellow
Write-Host "  Nexus - Azure Container App Deployment"    -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Resource Group:    $ResourceGroup"
Write-Host "  Location:          $Location"
Write-Host "  Container App:     $AppName"
Write-Host "  Environment:       $EnvironmentName"
Write-Host "  ACR:               $RegistryName"
Write-Host "  Storage Account:   $StorageAccountName"
Write-Host ""

# ---------- 1. Resource Group ----------
Write-Step "Creating Resource Group '$ResourceGroup'..."
az group create --name $ResourceGroup --location $Location --output none

# ---------- 2. Azure Container Registry ----------
Write-Step "Creating Azure Container Registry '$RegistryName'..."
az acr create --resource-group $ResourceGroup --name $RegistryName --sku Basic --admin-enabled true --output none

$acrCreds = az acr credential show --name $RegistryName | ConvertFrom-Json
$acrServer   = "$($RegistryName).azurecr.io"
$acrUsername = $acrCreds.username
$acrPassword = $acrCreds.passwords[0].value

# ---------- 3. Build & push image ----------
Write-Step "Building and pushing Docker image..."
az acr build --registry $RegistryName --image nexus:latest --file ./Dockerfile . --no-logs --output none

# ---------- 4. Storage Account & File Shares ----------
Write-Step "Creating Storage Account '$StorageAccountName' and file shares..."
az storage account create `
    --resource-group $ResourceGroup `
    --name $StorageAccountName `
    --location $Location `
    --sku Standard_LRS `
    --kind StorageV2 `
    --output none

$storageKey = (az storage account keys list --resource-group $ResourceGroup --account-name $StorageAccountName | ConvertFrom-Json)[0].value

# Create file shares for persistent module storage and config
foreach ($shareName in @('nexus-conf', 'ps-modules', 'py-packages')) {
    az storage share create `
        --name $shareName `
        --account-name $StorageAccountName `
        --account-key $storageKey `
        --output none
    Write-Host "  Created file share: $shareName"
}

# ---------- 5. Container Apps Environment ----------
Write-Step "Creating Container Apps Environment '$EnvironmentName'..."
az containerapp env create `
    --resource-group $ResourceGroup `
    --name $EnvironmentName `
    --location $Location `
    --output none

# ---------- 6. Link storage to environment ----------
Write-Step "Linking storage account to environment..."
az containerapp env storage set `
    --resource-group $ResourceGroup `
    --name $EnvironmentName `
    --storage-name nexusfiles `
    --azure-file-account-name $StorageAccountName `
    --azure-file-account-key $storageKey `
    --azure-file-share-name nexus-conf `
    --access-mode ReadWrite `
    --output none

# Container Apps allows one share per storage link, so we create 3 links
az containerapp env storage set `
    --resource-group $ResourceGroup `
    --name $EnvironmentName `
    --storage-name nexuspsmodules `
    --azure-file-account-name $StorageAccountName `
    --azure-file-account-key $storageKey `
    --azure-file-share-name ps-modules `
    --access-mode ReadWrite `
    --output none

az containerapp env storage set `
    --resource-group $ResourceGroup `
    --name $EnvironmentName `
    --storage-name nexuspypackages `
    --azure-file-account-name $StorageAccountName `
    --azure-file-account-key $storageKey `
    --azure-file-share-name py-packages `
    --access-mode ReadWrite `
    --output none

# ---------- 7. Create Container App ----------
Write-Step "Creating Container App '$AppName'..."

# Build the YAML config for the container app (volumes + mounts require YAML)
$yamlContent = @"
properties:
  managedEnvironmentId: /subscriptions/$(az account show --query id -o tsv)/resourceGroups/$ResourceGroup/providers/Microsoft.App/managedEnvironments/$EnvironmentName
  configuration:
    ingress:
      external: true
      targetPort: 8080
      transport: auto
    registries:
      - server: $acrServer
        username: $acrUsername
        passwordSecretRef: acr-password
    secrets:
      - name: acr-password
        value: "$acrPassword"
      - name: azure-client-id
        value: "$AzureClientId"
      - name: azure-client-secret
        value: "$AzureClientSecret"
      - name: azure-tenant-id
        value: "$AzureTenantId"
  template:
    containers:
      - name: nexus-app
        image: $imageName
        resources:
          cpu: 1.0
          memory: 2Gi
        env:
          - name: POWERSHELL_TELEMETRY_OPTOUT
            value: "1"
          - name: AZURE_CLIENT_ID
            secretRef: azure-client-id
          - name: AZURE_CLIENT_SECRET
            secretRef: azure-client-secret
          - name: AZURE_TENANT_ID
            secretRef: azure-tenant-id
        volumeMounts:
          - volumeName: nexus-conf
            mountPath: /app/conf
          - volumeName: ps-modules
            mountPath: /usr/local/share/powershell/Modules
          - volumeName: py-packages
            mountPath: /usr/local/lib/python3.10/dist-packages
    scale:
      minReplicas: 1
      maxReplicas: 1
    volumes:
      - name: nexus-conf
        storageName: nexusfiles
        storageType: AzureFile
      - name: ps-modules
        storageName: nexuspsmodules
        storageType: AzureFile
      - name: py-packages
        storageName: nexuspypackages
        storageType: AzureFile
"@

$yamlPath = Join-Path $PSScriptRoot 'container-app.yaml'
$yamlContent | Set-Content -Path $yamlPath -Encoding UTF8

az containerapp create `
    --resource-group $ResourceGroup `
    --name $AppName `
    --yaml $yamlPath `
    --output none

Remove-Item $yamlPath -Force -ErrorAction SilentlyContinue

# ---------- 8. Output ----------
Write-Step "Deployment complete!"
$fqdn = az containerapp show --resource-group $ResourceGroup --name $AppName --query 'properties.configuration.ingress.fqdn' -o tsv

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Nexus is running at:" -ForegroundColor Green
Write-Host "  https://$fqdn" -ForegroundColor White
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  ACR Registry:      $acrServer"
Write-Host "  Storage Account:   $StorageAccountName"
Write-Host "  Resource Group:    $ResourceGroup"
Write-Host ""
Write-Host "Save these values for Update-Nexus.ps1:" -ForegroundColor Yellow
Write-Host "  -ResourceGroup $ResourceGroup -RegistryName $RegistryName -AppName $AppName" -ForegroundColor Yellow
