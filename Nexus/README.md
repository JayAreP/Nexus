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
{workflow-name}/     per-workflow container with logs/ subfolder
```

Only `conf/config.json` (storage account credentials) is stored locally.

## Stack

Pode (PowerShell web framework), Az.Storage module, Docker, vanilla JS frontend.

## Environment variables

Set these in docker-compose.yml for Azure service principal auth:
- `AZURE_CLIENT_ID`
- `AZURE_CLIENT_SECRET`
- `AZURE_TENANT_ID`
