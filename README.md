# Nexus - Automation Sequencer

## Prerequisites

Before starting you'll need an Azure Service Principal and an encryption key for the credential store.

### Create a Service Principal

```powershell
az ad sp create-for-rbac --name "nexus-sp" --skip-assignment
```

Output:
```json
{
  "appId":    "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",   ← AZURE_CLIENT_ID
  "password": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", ← AZURE_CLIENT_SECRET
  "tenant":   "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"    ← AZURE_TENANT_ID
}
```

> Save the `password` immediately — it cannot be retrieved after creation.  
> To reset later: `az ad sp credential reset --name "nexus-sp"`

### Generate a NEXUS_CREDENTIAL_KEY

Secret fields are encrypted with AES-256. The key must be a 32-byte base64-encoded value.

PowerShell:
```powershell
[Convert]::ToBase64String((1..32 | ForEach-Object { [byte](Get-Random -Max 256) }))
```

Bash / Linux:
```bash
openssl rand -base64 32
```

Keep this value consistent between restarts — changing it will invalidate stored credentials.

---

## Quick Start (local build)

This builds the image from source. For deploying the pre-published image from GHCR, see [Deploy-to-ACA.md](Deploy-to-ACA.md).

### 1. Create your `.env` file

Copy `.env.example` to `.env` and fill in your values:
```
AZURE_CLIENT_ID=your-client-id
AZURE_CLIENT_SECRET=your-client-secret
AZURE_TENANT_ID=your-tenant-id
NEXUS_CREDENTIAL_KEY=your-base64-32-byte-key
```

See [Azure Setup](#azure-setup) below for how to create the service principal and generate the credential key.

### 2. Create the conf directory

```
mkdir conf
```

### 3. Create a `docker-compose.yml`

```yaml
services:
  nexus-web:
    build: .
    container_name: nexus-app
    ports:
      - "8082:8080"
    volumes:
      - ./conf:/app/conf
      - ./Scripts:/app/Scripts:ro
      - nexus-ps-modules:/usr/local/share/powershell/Modules
      - nexus-py-packages:/usr/local/lib/python3.10/dist-packages
    environment:
      - POWERSHELL_TELEMETRY_OPTOUT=1
      - AZURE_CLIENT_ID=${AZURE_CLIENT_ID}
      - AZURE_CLIENT_SECRET=${AZURE_CLIENT_SECRET}
      - AZURE_TENANT_ID=${AZURE_TENANT_ID}
      - NEXUS_CREDENTIAL_KEY=${NEXUS_CREDENTIAL_KEY}
    restart: unless-stopped
    networks:
      - nexus-network

networks:
  nexus-network:
    driver: bridge

volumes:
  nexus-ps-modules:
  nexus-py-packages:
```

> **Note on volumes:**
> - `./conf` — persists local config (`config.json`) across restarts
> - `./Scripts` — mounted read-only so you can edit scripts without rebuilding
> - `nexus-ps-modules` / `nexus-py-packages` — named volumes so installed modules survive container recreates

### 4. Build and start

```
docker-compose up -d --build
```

The first build takes several minutes (installs PS modules, Azure CLI, AWS CLI, GCloud CLI, Terraform).  
Subsequent starts reuse the cached layers and are fast.

### 5. Open the app

```
http://localhost:8082
```

Go to **Configuration** and enter your storage account name to initialise the blob containers.

### Updating after code changes

`./Scripts` is live-mounted — edits there take effect immediately with no restart needed.

For changes to `Server.ps1` or `public/`:
```
docker-compose up -d --build
```

### Stopping / restarting

```bash
docker-compose down       # stop and remove containers (volumes preserved)
docker-compose restart    # restart without rebuild
```

## What it does

Nexus lets you build linear automation workflows ("ladders") by chaining steps together. Each step can be a PowerShell script, Terraform plan, Python script, Shell script, or Webhook call. Steps run sequentially — if one fails, the chain stops.

Steps take key/value parameters that get translated per type:
- **PowerShell** — splatted as `-Key Value`
- **Terraform** — written as `key = "value"` in a .tfvars file
- **Python** — passed as `--key value` CLI args
- **Shell** — set as environment variables
- **Webhook** — sent as JSON body `{ "key": "value" }`

Steps can capture JSON output and pass it to later steps via input mappings.

## Panels

| Panel | What it does |
|---|---|
| **Workflows** | Build and edit step ladders — add steps, set params, configure output capture and input mapping |
| **Scripts** | Upload scripts to blob storage by type (PowerShell, Terraform, Python, Shell) |
| **Webhooks** | Configure webhook endpoints with optional OAuth (client credentials flow) |
| **Credentials** | Store and manage encrypted credentials (passwords, service principals, API keys, AWS/GCP keys) |
| **Run / Schedule** | Run workflows manually or create recurring schedules (hourly/daily/weekly/monthly) |
| **Logs** | View per-workflow run logs with step-by-step output and status |
| **Modules** | Browse and manage installed PowerShell and Python modules |
| **Sandbox** | Restricted web terminal for testing scripts — runs as unprivileged `sandbox` user |
| **Configuration** | Set storage account credentials and prepare containers |

## Storage layout

Everything lives in Azure Blob Storage:
```
nexus-config/        workflows/ and schedules/ JSON definitions
nexus-powershell/    uploaded .ps1 scripts
nexus-terraform/     uploaded .tf files
nexus-python/        uploaded .py scripts
nexus-shell/         uploaded .sh scripts
nexus-webhooks/      webhook config JSON files
nexus-credentials/   encrypted credential JSON files
{workflow-name}/     per-workflow container with logs/ subfolder
```

Only `conf/config.json` (storage account credentials) is stored locally.

## Stack

Pode (PowerShell web framework), Az.Storage module, Docker, vanilla JS frontend.

## Azure Setup

See [Prerequisites](#prerequisites) above for creating the service principal.

### 1. Assign Storage Roles

Nexus only needs access to Azure Blob Storage. Assign these two roles on the **storage account** (not the subscription) to follow least-privilege:

| Role | Purpose |
|------|---------|
| `Storage Blob Data Contributor` | Read, write, and delete blobs (workflows, scripts, logs, credentials) |
| `Storage Blob Data Reader` | *(Optional)* Read-only access if you want a separate read account |

```powershell
# Get the service principal's object ID
$spId = az ad sp show --id "<AZURE_CLIENT_ID>" --query id -o tsv

# Assign Storage Blob Data Contributor on the storage account
az role assignment create `
  --assignee $spId `
  --role "Storage Blob Data Contributor" `
  --scope "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/<RESOURCE_GROUP>/providers/Microsoft.Storage/storageAccounts/<STORAGE_ACCOUNT_NAME>"
```

If you prefer to scope at the resource group level instead (simpler, slightly broader):

```powershell
az role assignment create `
  --assignee $spId `
  --role "Storage Blob Data Contributor" `
  --scope "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/<RESOURCE_GROUP>"
```

> **Note:** `Storage Blob Data Contributor` is sufficient for all Nexus operations. Do **not** assign `Contributor` or `Owner` at the subscription level — Nexus does not need control-plane access.

### 2. Verify access

```powershell
az login --service-principal `
  -u "<AZURE_CLIENT_ID>" `
  -p "<AZURE_CLIENT_SECRET>" `
  --tenant "<AZURE_TENANT_ID>"

az storage blob list `
  --account-name "<STORAGE_ACCOUNT_NAME>" `
  --container-name "nexus-config" `
  --auth-mode login
```

---

## Environment variables

Set these in `.env` (read by docker-compose):

- `AZURE_CLIENT_ID` — Service principal app ID
- `AZURE_CLIENT_SECRET` — Service principal secret
- `AZURE_TENANT_ID` — Azure AD tenant ID
- `NEXUS_CREDENTIAL_KEY` — AES-256 encryption key for the credential store (see below)

## Credential Store

The Credentials panel lets you store secrets (passwords, Azure service principals, AWS keys, GCP service accounts, API keys, tokens, connection strings) encrypted at rest in blob storage.

Secret fields are encrypted with AES-256 using `NEXUS_CREDENTIAL_KEY`. See [Prerequisites](#prerequisites) above for how to generate the key. Add it to your `.env` file and recreate the container (`docker-compose up -d`) for any change to take effect.

### NLS Client Modules

Workflow scripts can retrieve credentials at runtime using the **NLS** (Nexus Ladder Scheduler) client modules, which are pre-installed in the container.

**PowerShell:**
```powershell
Import-Module NLS
$creds = Get-NLSCredential -Name 'prod-db-login'
$creds.username
$creds.password
```

**Python:**
```python
import nls
creds = nls.get_credential("prod-db-login")
creds["username"]
creds["password"]
```

**Direct API:**
```
GET http://localhost:8080/api/credentials/{name}/resolve
```

## Sandbox

The Sandbox panel provides a web-based terminal running as a restricted `sandbox` user inside the container. Use it to interactively test scripts, import modules, and run ad-hoc commands without affecting the main application.

**Available tools:** `pwsh`, `python3`, `terraform`, `bash`, plus any modules/packages installed in the container.

**Security:**
- Runs as unprivileged user `sandbox` (no root, no sudo)
- Working directory: `/home/sandbox/workspace`
- Served by [ttyd](https://github.com/tsl0922/ttyd) on port **7681**

The terminal is embedded in the Nexus UI. You can also open it directly at `http://<host>:7681` or click **Open in New Tab**.

## Interactive container access

```
docker exec -it nexus-app pwsh
```
