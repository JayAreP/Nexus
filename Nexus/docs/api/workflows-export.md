# Export Workflow

Exports a workflow definition, optionally bundling referenced webhook and filecheck configurations.

## Request

`GET /api/workflows/:name/export`

### Headers

| Header          | Value              | Required |
|-----------------|--------------------|----------|
| Authorization   | Bearer {token}     | Yes      |

### Parameters

| Parameter  | In    | Type   | Required | Description                                      |
|------------|-------|--------|----------|--------------------------------------------------|
| name       | path  | string | Yes      | Name of the workflow to export                   |
| webhooks   | query | string | No       | `"true"` to include referenced webhooks          |
| filechecks | query | string | No       | `"true"` to include referenced filecheck configs |

### Example Request (curl)

```bash
curl -X GET "http://nexus:8080/api/workflows/nightly-deploy/export?webhooks=true&filechecks=true" -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIs..."
```

## Response

### Success (200)

```json
{
  "success": true,
  "export": {
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

### Error (4xx)

| Status | Body                                                          |
|--------|---------------------------------------------------------------|
| 401    | `{ "success": false, "message": "Unauthorized" }`            |
| 404    | `{ "success": false, "message": "Workflow not found" }`      |

## Notes

- When `webhooks` or `filechecks` query params are omitted or `"false"`, those arrays are empty in the response.
- Useful for migrating workflows between Nexus instances.
