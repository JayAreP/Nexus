# Get Script Content

Returns the full source content of a specific script.

## Request

`GET /api/scripts/:type/:name/content`

### Headers

| Header          | Value              | Required |
|-----------------|--------------------|----------|
| Authorization   | Bearer {token}     | Yes      |

### Parameters

| Parameter | In   | Type   | Required | Description                                          |
|-----------|------|--------|----------|------------------------------------------------------|
| type      | path | string | Yes      | One of: `powershell`, `python`, `terraform`, `shell` |
| name      | path | string | Yes      | Script filename (e.g. `Deploy.ps1`)                  |

### Example Request (curl)

```bash
curl -X GET "http://nexus:8080/api/scripts/powershell/Deploy.ps1/content" -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIs..."
```

## Response

### Success (200)

```json
{
  "success": true,
  "content": "param([string]$Name)\nWrite-Host \"Hello, $Name\"",
  "name": "Deploy.ps1"
}
```

### Error (4xx)

| Status | Body                                                     |
|--------|----------------------------------------------------------|
| 401    | `{ "success": false, "message": "Unauthorized" }`       |
| 404    | `{ "success": false, "message": "Script not found" }`   |

## Notes

- The content is returned as a plain string with the original line endings preserved.
