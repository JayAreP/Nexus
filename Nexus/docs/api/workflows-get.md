# Get Workflow

Returns the full definition of a single workflow by name.

## Request

`GET /api/workflows/:name`

### Headers

| Header          | Value              | Required |
|-----------------|--------------------|----------|
| Authorization   | Bearer {token}     | Yes      |

### Parameters

| Parameter | In   | Type   | Required | Description          |
|-----------|------|--------|----------|----------------------|
| name      | path | string | Yes      | Name of the workflow |

### Example Request (curl)

```bash
curl -X GET "http://nexus:8080/api/workflows/nightly-deploy" -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIs..."
```

## Response

### Success (200)

```json
{
  "success": true,
  "workflow": {
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
}
```

### Error (4xx)

| Status | Body                                                          |
|--------|---------------------------------------------------------------|
| 401    | `{ "success": false, "message": "Unauthorized" }`            |
| 404    | `{ "success": false, "message": "Workflow not found" }`      |

## Notes

- The returned object includes all properties stored in the workflow definition.
