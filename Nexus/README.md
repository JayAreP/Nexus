# Nexus - Automation Sequencer

Run it with Docker:
```
docker-compose up -d --build
```
Then open http://localhost:8082

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

## Environment variables

Set these in `.env` (read by docker-compose):

- `AZURE_CLIENT_ID` — Service principal app ID
- `AZURE_CLIENT_SECRET` — Service principal secret
- `AZURE_TENANT_ID` — Azure AD tenant ID
- `NEXUS_CREDENTIAL_KEY` — AES-256 encryption key for the credential store (see below)

## Credential Store

The Credentials panel lets you store secrets (passwords, Azure service principals, AWS keys, GCP service accounts, API keys, tokens, connection strings) encrypted at rest in blob storage.

Secret fields are encrypted with AES-256 using the `NEXUS_CREDENTIAL_KEY` environment variable. This key must be a 32-byte value, base64-encoded.

### Generate a credential key

PowerShell:
```powershell
[Convert]::ToBase64String((1..32 | ForEach-Object { [byte](Get-Random -Max 256) }))
```

Bash / Linux:
```bash
openssl rand -base64 32
```

Add the result to your `.env` file:
```
NEXUS_CREDENTIAL_KEY=your-generated-key-here
```

Then recreate the container (`docker-compose up -d`) for the new env var to take effect.

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

## Interactive container access

```
docker exec -it nexus-app pwsh
```
