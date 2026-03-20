# Deploying Nexus to Azure Container Apps from GHCR

This guide deploys the pre-built image from `ghcr.io/jayarep/nexus:latest` directly into an Azure Container App.  
No Docker, no ACR, no local build required.

---

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) installed
- Logged in: `az login`
- A Service Principal with blob storage access (for Nexus to function)
- The four values from your `.env` file ready:
  - `AZURE_CLIENT_ID`
  - `AZURE_CLIENT_SECRET`
  - `AZURE_TENANT_ID`
  - `NEXUS_CREDENTIAL_KEY`

---

## Prerequisite A — Create an Azure Service Principal

Nexus uses a Service Principal to authenticate against Azure (blob storage, etc.). Run this once.

```bash
# Create the SP and assign Contributor role on the subscription
# (scope it to a specific resource group instead if you prefer least-privilege)
az ad sp create-for-rbac --name "nexus-sp" --role Contributor --scopes /subscriptions/<SUBSCRIPTION_ID>
```

Output:
```json
{
  "appId":       "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",   ← AZURE_CLIENT_ID
  "password":    "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", ← AZURE_CLIENT_SECRET
  "tenant":      "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"    ← AZURE_TENANT_ID
}
```

> **Save these immediately** — the `password` is only shown once and cannot be retrieved later.

If you already have a Service Principal and need to reset its secret:
```bash
az ad sp credential reset --name "nexus-sp"
```

---

## Prerequisite B — Generate a NEXUS_CREDENTIAL_KEY

`NEXUS_CREDENTIAL_KEY` is a stable encryption key used by Nexus to protect stored credentials. It should be a strong random string. Use any of these methods:

**PowerShell:**
```powershell
-join ((65..90) + (97..122) + (48..57) | Get-Random -Count 32 | ForEach-Object { [char]$_ })
```

**PowerShell (SHA256 of a passphrase — deterministic, easy to regenerate):**
```powershell
$phrase = "your-memorable-passphrase"
$bytes  = [System.Text.Encoding]::UTF8.GetBytes($phrase)
$hash   = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
[System.BitConverter]::ToString($hash).Replace('-','').ToLower()
```

**Bash / Linux:**
```bash
echo -n "your-memorable-passphrase" | sha256sum | awk '{print $1}'
# or purely random:
openssl rand -hex 32
```

> Use the **same value** every deployment — changing it will invalidate any credentials Nexus has stored in `/app/conf`.

---

## Concepts: docker-compose vs Azure Container Apps

| docker-compose concept        | ACA equivalent                                  |
|-------------------------------|-------------------------------------------------|
| `image:`                      | `--image` on `az containerapp create`           |
| `environment:` (plain)        | `--env-vars KEY=value`                          |
| `environment:` (secret)       | Stored as a **Secret**, referenced by name      |
| `volumes:` (named volume)     | Azure File Share linked to the ACA Environment  |
| `ports:`                      | **Ingress** config (`targetPort: 8080`)         |
| `restart: unless-stopped`     | `minReplicas: 1` in scale config                |
| `.env` file                   | Secrets set at create time (see Step 5)         |

---

## Step 1 — Set variables

Run these in your shell session. Replace the placeholder values.

```bash
RG="nexus-rg"
LOCATION="australiaeast"
APP_NAME="nexus-app"
ENV_NAME="nexus-env"
STORAGE_NAME="nexusfiles$RANDOM"   # must be globally unique, 3-24 chars lowercase

AZURE_CLIENT_ID="<your-client-id>"
AZURE_CLIENT_SECRET="<your-client-secret>"
AZURE_TENANT_ID="<your-tenant-id>"
NEXUS_CREDENTIAL_KEY="<any-random-string-keep-consistent>"
```

**If you are using PowerShell:**
```powershell
$RG = "nexus-rg"
$LOCATION = "australiaeast"
$APP_NAME = "nexus-app"
$ENV_NAME = "nexus-env"
$STORAGE_NAME = "nexusfiles$(Get-Random -Maximum 99999)"   # must be globally unique, 3-24 chars lowercase

$AZURE_CLIENT_ID = "<your-client-id>"
$AZURE_CLIENT_SECRET = "<your-client-secret>"
$AZURE_TENANT_ID = "<your-tenant-id>"
$NEXUS_CREDENTIAL_KEY = "<any-random-string-keep-consistent>"
```

---

## Step 2 — Create Resource Group

```bash
az group create --name $RG --location $LOCATION
```

---

## Step 3 — Create Container Apps Environment

This is the hosting environment — equivalent to the Docker network/host.

```bash
az containerapp env create --resource-group $RG --name $ENV_NAME --location $LOCATION
```

---

## Step 4 — Create Storage Account and File Shares

These replace the **named volumes** in docker-compose (`nexus-ps-modules`, `nexus-py-packages`, and `./conf`).

```bash
# Create storage account
az storage account create --resource-group $RG --name $STORAGE_NAME --location $LOCATION --sku Standard_LRS --kind StorageV2

# Get the storage key
STORAGE_KEY=$(az storage account keys list --resource-group $RG --account-name $STORAGE_NAME --query '[0].value' -o tsv)

# If you are using PowerShell:
# $STORAGE_KEY = az storage account keys list --resource-group $RG --account-name $STORAGE_NAME --query '[0].value' -o tsv

# Create the three file shares
az storage share create --name nexus-conf     --account-name $STORAGE_NAME --account-key $STORAGE_KEY
az storage share create --name ps-modules     --account-name $STORAGE_NAME --account-key $STORAGE_KEY
az storage share create --name py-packages    --account-name $STORAGE_NAME --account-key $STORAGE_KEY
```

### Link the shares to the Container Apps Environment

ACA requires each share to be registered with the environment before it can be mounted.

```bash
az containerapp env storage set --resource-group $RG --name $ENV_NAME --storage-name nexusconf --azure-file-account-name $STORAGE_NAME --azure-file-account-key $STORAGE_KEY --azure-file-share-name nexus-conf --access-mode ReadWrite

az containerapp env storage set --resource-group $RG --name $ENV_NAME --storage-name nexuspsmodules --azure-file-account-name $STORAGE_NAME --azure-file-account-key $STORAGE_KEY --azure-file-share-name ps-modules --access-mode ReadWrite

az containerapp env storage set --resource-group $RG --name $ENV_NAME --storage-name nexuspypackages --azure-file-account-name $STORAGE_NAME --azure-file-account-key $STORAGE_KEY --azure-file-share-name py-packages --access-mode ReadWrite
```

---

## Step 5 — Create the Container App

This is a two-part process: first create the app with CLI flags, then update it with a YAML file to add volume mounts (which can only be declared via YAML).

### 5a — Create the app

Replace each `<PLACEHOLDER>` with the actual secret value (from Prerequisite A and B), not the variable name.

```bash
az containerapp create -n $APP_NAME -g $RG --environment $ENV_NAME --image ghcr.io/jayarep/nexus:latest --target-port 8080 --ingress external --cpu 1.0 --memory 2Gi --min-replicas 1 --max-replicas 1 --secrets azure-client-id="<AZURE_CLIENT_ID>" azure-client-secret="<AZURE_CLIENT_SECRET>" azure-tenant-id="<AZURE_TENANT_ID>" nexus-credential-key="<NEXUS_CREDENTIAL_KEY>" --env-vars POWERSHELL_TELEMETRY_OPTOUT="1" AZURE_CLIENT_ID=secretref:azure-client-id AZURE_CLIENT_SECRET=secretref:azure-client-secret AZURE_TENANT_ID=secretref:azure-tenant-id NEXUS_CREDENTIAL_KEY=secretref:nexus-credential-key
```

Where each secret value is:
- `<AZURE_CLIENT_ID>` -- the `appId` from `az ad sp create-for-rbac` (Prerequisite A)
- `<AZURE_CLIENT_SECRET>` -- the `password` from `az ad sp create-for-rbac` (Prerequisite A)
- `<AZURE_TENANT_ID>` -- the `tenant` from `az ad sp create-for-rbac` (Prerequisite A)
- `<NEXUS_CREDENTIAL_KEY>` -- the key you generated in Prerequisite B

> **Note:** The image is public on GHCR so no registry credentials are needed. If you make the package private, add a `registries:` block with a GitHub PAT (`read:packages` scope).

### 5b — Add volume mounts via YAML

Save the following as `containerapp.yaml` (no comments, no special characters):

```yaml
properties:
  template:
    containers:
      - name: nexus-app
        image: ghcr.io/jayarep/nexus:latest
        resources:
          cpu: 1.0
          memory: 2Gi
        volumeMounts:
          - volumeName: nexus-conf
            mountPath: /app/conf
          - volumeName: ps-modules
            mountPath: /usr/local/share/powershell/Modules
          - volumeName: py-packages
            mountPath: /usr/local/lib/python3.10/dist-packages
    volumes:
      - name: nexus-conf
        storageName: nexusconf
        storageType: AzureFile
      - name: ps-modules
        storageName: nexuspsmodules
        storageType: AzureFile
      - name: py-packages
        storageName: nexuspypackages
        storageType: AzureFile
```

Then update the app to attach the volumes:

```bash
az containerapp update -n $APP_NAME -g $RG --yaml containerapp.yaml
```

---

## Step 6 — Get the URL

```bash
az containerapp show --resource-group $RG --name $APP_NAME --query 'properties.configuration.ingress.fqdn' -o tsv
```

Open `https://<fqdn>` in a browser.

---

## Updating to a new version

After publishing a new image to GHCR:

```bash
az containerapp update --resource-group $RG --name $APP_NAME --image ghcr.io/jayarep/nexus:latest
```

ACA will pull the new `latest` and perform a zero-downtime revision swap.

---

## Environment variable reference (.env → ACA secrets)

| `.env` key              | ACA secret name          | Mount path / purpose                          |
|-------------------------|--------------------------|-----------------------------------------------|
| `AZURE_CLIENT_ID`       | `azure-client-id`        | Service principal for blob access             |
| `AZURE_CLIENT_SECRET`   | `azure-client-secret`    | Service principal secret                      |
| `AZURE_TENANT_ID`       | `azure-tenant-id`        | Azure tenant                                  |
| `NEXUS_CREDENTIAL_KEY`  | `nexus-credential-key`   | Encryption key for stored credentials         |

## Volume reference (docker-compose → ACA)

| docker-compose volume              | ACA storage name    | Mount path                                    |
|------------------------------------|---------------------|-----------------------------------------------|
| `./conf`                           | `nexusconf`         | `/app/conf`                                   |
| `nexus-ps-modules`                 | `nexuspsmodules`    | `/usr/local/share/powershell/Modules`         |
| `nexus-py-packages`                | `nexuspypackages`   | `/usr/local/lib/python3.10/dist-packages`     |
