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

---

## Step 2 — Create Resource Group

```bash
az group create --name $RG --location $LOCATION
```

---

## Step 3 — Create Container Apps Environment

This is the hosting environment — equivalent to the Docker network/host.

```bash
az containerapp env create \
  --resource-group $RG \
  --name $ENV_NAME \
  --location $LOCATION
```

---

## Step 4 — Create Storage Account and File Shares

These replace the **named volumes** in docker-compose (`nexus-ps-modules`, `nexus-py-packages`, and `./conf`).

```bash
# Create storage account
az storage account create \
  --resource-group $RG \
  --name $STORAGE_NAME \
  --location $LOCATION \
  --sku Standard_LRS \
  --kind StorageV2

# Get the storage key
STORAGE_KEY=$(az storage account keys list \
  --resource-group $RG \
  --account-name $STORAGE_NAME \
  --query '[0].value' -o tsv)

# Create the three file shares
az storage share create --name nexus-conf     --account-name $STORAGE_NAME --account-key $STORAGE_KEY
az storage share create --name ps-modules     --account-name $STORAGE_NAME --account-key $STORAGE_KEY
az storage share create --name py-packages    --account-name $STORAGE_NAME --account-key $STORAGE_KEY
```

### Link the shares to the Container Apps Environment

ACA requires each share to be registered with the environment before it can be mounted.

```bash
az containerapp env storage set \
  --resource-group $RG --name $ENV_NAME \
  --storage-name nexusconf \
  --azure-file-account-name $STORAGE_NAME --azure-file-account-key $STORAGE_KEY \
  --azure-file-share-name nexus-conf --access-mode ReadWrite

az containerapp env storage set \
  --resource-group $RG --name $ENV_NAME \
  --storage-name nexuspsmodules \
  --azure-file-account-name $STORAGE_NAME --azure-file-account-key $STORAGE_KEY \
  --azure-file-share-name ps-modules --access-mode ReadWrite

az containerapp env storage set \
  --resource-group $RG --name $ENV_NAME \
  --storage-name nexuspypackages \
  --azure-file-account-name $STORAGE_NAME --azure-file-account-key $STORAGE_KEY \
  --azure-file-share-name py-packages --access-mode ReadWrite
```

---

## Step 5 — Create the Container App

Volumes and volume mounts can only be declared via a YAML spec (not CLI flags alone).  
Save the following as `containerapp.yaml`, substituting your values:

```yaml
properties:
  managedEnvironmentId: /subscriptions/<SUBSCRIPTION_ID>/resourceGroups/<RG>/providers/Microsoft.App/managedEnvironments/<ENV_NAME>
  # ^ All three parts are known values:
  #   SUBSCRIPTION_ID  = output of: az account show --query id -o tsv
  #   RG               = your $RG from Step 1  (e.g. nexus-rg)
  #   ENV_NAME         = your $ENV_NAME from Step 1, created in Step 3  (e.g. nexus-env)
  configuration:
    ingress:
      external: true
      targetPort: 8080
      transport: auto
    secrets:
      - name: azure-client-id
        value: "<AZURE_CLIENT_ID>"
      - name: azure-client-secret
        value: "<AZURE_CLIENT_SECRET>"
      - name: azure-tenant-id
        value: "<AZURE_TENANT_ID>"
      - name: nexus-credential-key
        value: "<NEXUS_CREDENTIAL_KEY>"
  template:
    containers:
      - name: nexus-app
        image: ghcr.io/jayarep/nexus:latest
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
          - name: NEXUS_CREDENTIAL_KEY
            secretRef: nexus-credential-key
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
        storageName: nexusconf
        storageType: AzureFile
      - name: ps-modules
        storageName: nexuspsmodules
        storageType: AzureFile
      - name: py-packages
        storageName: nexuspypackages
        storageType: AzureFile
```

> **Note:** The image is public on GHCR so no registry credentials are needed. If you make the package private, add a `registries:` block with a GitHub PAT (`read:packages` scope).

Before writing the YAML, build the full environment resource ID:
```bash
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
MANAGED_ENV_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.App/managedEnvironments/$ENV_NAME"
echo $MANAGED_ENV_ID
```

Paste the output of `echo $MANAGED_ENV_ID` into the `managedEnvironmentId:` field in `containerapp.yaml` — all three parts (`$SUBSCRIPTION_ID`, `$RG`, `$ENV_NAME`) are values you already set in Steps 1–3.

Then deploy:
```bash
az containerapp create \
  --resource-group $RG \
  --name $APP_NAME \
  --yaml containerapp.yaml
```

---

## Step 6 — Get the URL

```bash
az containerapp show \
  --resource-group $RG \
  --name $APP_NAME \
  --query 'properties.configuration.ingress.fqdn' -o tsv
```

Open `https://<fqdn>` in a browser.

---

## Updating to a new version

After publishing a new image to GHCR:

```bash
az containerapp update \
  --resource-group $RG \
  --name $APP_NAME \
  --image ghcr.io/jayarep/nexus:latest
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
