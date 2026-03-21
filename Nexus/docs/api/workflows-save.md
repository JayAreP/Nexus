# Save Workflow

Creates a new workflow or updates an existing one.

## Request

`POST /api/workflows`

### Headers

| Header          | Value              | Required |
|-----------------|--------------------|----------|
| Authorization   | Bearer {token}     | Yes      |
| Content-Type    | application/json   | Yes      |

### Body

A complete workflow JSON definition. Must include at least a `name` field and a `steps` array.

```json
{
  "name": "nightly-deploy",
  "steps": [
    {
      "name": "Pull latest",
      "type": "powershell",
      "script": "GitPull.ps1",
      "args": ""
    },
    {
      "name": "Run migrations",
      "type": "python",
      "script": "migrate.py",
      "args": "--env production"
    }
  ]
}
```

### Example Request (curl)

```bash
curl -X POST "http://nexus:8080/api/workflows" -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIs..." -H "Content-Type: application/json" -d '{"name":"nightly-deploy","steps":[{"name":"Pull latest","type":"powershell","script":"GitPull.ps1","args":""}]}'
```

## Response

### Success (200)

```json
{
  "success": true,
  "message": "Workflow 'nightly-deploy' saved"
}
```

### Error (4xx)

| Status | Body                                                  |
|--------|-------------------------------------------------------|
| 401    | `{ "success": false, "message": "Unauthorized" }`    |

## Notes

- Creates or updates. If a workflow with the given name already exists it is overwritten.
- Auto-creates a per-workflow log container for storing console output.
