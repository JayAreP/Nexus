# List Scripts

Returns all scripts stored in a given type-specific storage container.

## Request

`GET /api/scripts/:type`

### Headers

| Header          | Value              | Required |
|-----------------|--------------------|----------|
| Authorization   | Bearer {token}     | Yes      |

### Parameters

| Parameter | In   | Type   | Required | Description                                          |
|-----------|------|--------|----------|------------------------------------------------------|
| type      | path | string | Yes      | One of: `powershell`, `python`, `terraform`, `shell` |

### Example Request (curl)

```bash
curl -X GET "http://nexus:8080/api/scripts/powershell" -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIs..."
```

## Response

### Success (200)

```json
{
  "success": true,
  "scripts": [
    {
      "name": "Deploy.ps1",
      "lastModified": "2026-03-21T10:00:00Z",
      "size": 2048
    },
    {
      "name": "Cleanup.ps1",
      "lastModified": "2026-03-20T14:30:00Z",
      "size": 1024
    }
  ]
}
```

### Error (4xx)

| Status | Body                                                  |
|--------|-------------------------------------------------------|
| 401    | `{ "success": false, "message": "Unauthorized" }`    |
| 400    | `{ "success": false, "message": "Invalid script type" }` |

## Notes

- Reads from the `nexus-{type}` storage container (e.g. `nexus-powershell`, `nexus-python`).
