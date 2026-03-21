# Import Workflow

Imports a workflow definition and optionally its associated webhook and filecheck configurations.

## Request

`POST /api/workflows/import`

### Headers

| Header          | Value              | Required |
|-----------------|--------------------|----------|
| Authorization   | Bearer {token}     | Yes      |
| Content-Type    | application/json   | Yes      |

### Body

```json
{
  "importWebhooks": true,
  "importFilechecks": true,
  "payload": {
    "workflow": {
      "name": "nightly-deploy",
      "steps": [
        {
          "name": "Pull latest",
          "type": "powershell",
          "script": "GitPull.ps1",
          "args": ""
        }
      ]
    },
    "webhooks": [
      {
        "id": "wh-001",
        "name": "deploy-trigger",
        "workflow": "nightly-deploy"
      }
    ],
    "filechecks": [
      {
        "id": "fc-001",
        "path": "C:\\deploy\\lock.flag",
        "workflow": "nightly-deploy"
      }
    ]
  }
}
```

| Field            | Type    | Required | Description                                    |
|------------------|---------|----------|------------------------------------------------|
| importWebhooks   | boolean | Yes      | Whether to import bundled webhook configs      |
| importFilechecks | boolean | Yes      | Whether to import bundled filecheck configs    |
| payload          | object  | Yes      | The export object from `/export`               |

### Example Request (curl)

```bash
curl -X POST "http://nexus:8080/api/workflows/import" -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIs..." -H "Content-Type: application/json" -d '{"importWebhooks":true,"importFilechecks":false,"payload":{"workflow":{"name":"nightly-deploy","steps":[]},"webhooks":[],"filechecks":[]}}'
```

## Response

### Success (200)

```json
{
  "success": true,
  "message": "Workflow 'nightly-deploy' imported"
}
```

### Error (4xx)

| Status | Body                                                                                                          |
|--------|---------------------------------------------------------------------------------------------------------------|
| 401    | `{ "success": false, "message": "Unauthorized" }`                                                            |
| 400    | `{ "success": false, "message": "Missing referenced scripts", "missingScripts": ["GitPull.ps1", "migrate.py"] }` |

## Notes

- Returns a `400` with a `missingScripts` array if the workflow references scripts that do not exist on the target instance.
- The `payload` object matches the shape returned by the export endpoint.
