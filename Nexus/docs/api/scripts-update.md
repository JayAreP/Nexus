# Update Script

Overwrites the content of an existing script.

## Request

`PUT /api/scripts/:type/:name`

### Headers

| Header          | Value              | Required |
|-----------------|--------------------|----------|
| Authorization   | Bearer {token}     | Yes      |
| Content-Type    | application/json   | Yes      |

### Parameters

| Parameter | In   | Type   | Required | Description                                          |
|-----------|------|--------|----------|------------------------------------------------------|
| type      | path | string | Yes      | One of: `powershell`, `python`, `terraform`, `shell` |
| name      | path | string | Yes      | Script filename (e.g. `Deploy.ps1`)                  |

### Body

```json
{
  "content": "param([string]$Name, [int]$Count = 1)\nWrite-Host \"Hello, $Name\" -ForegroundColor Green"
}
```

| Field   | Type   | Required | Description                |
|---------|--------|----------|----------------------------|
| content | string | Yes      | The full script source     |

### Example Request (curl)

```bash
curl -X PUT "http://nexus:8080/api/scripts/powershell/Deploy.ps1" -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIs..." -H "Content-Type: application/json" -d '{"content": "param([string]$Name)\nWrite-Host \"Updated script\""}'
```

## Response

### Success (200)

```json
{
  "success": true,
  "message": "Script updated"
}
```

### Error (4xx)

| Status | Body                                                     |
|--------|----------------------------------------------------------|
| 401    | `{ "success": false, "message": "Unauthorized" }`       |
| 400    | `{ "success": false, "message": "Content is required" }` |

## Notes

- Replaces the entire script content; there is no partial/patch update.
