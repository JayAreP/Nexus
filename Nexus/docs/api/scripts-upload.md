# Upload Script

Uploads a script file to the type-specific blob container.

## Request

`POST /api/scripts/:type`

### Headers

| Header          | Value              | Required |
|-----------------|--------------------|----------|
| Authorization   | Bearer {token}     | Yes      |
| Content-Type    | multipart/form-data | Yes     |

### Parameters

| Parameter | In   | Type   | Required | Description                                          |
|-----------|------|--------|----------|------------------------------------------------------|
| type      | path | string | Yes      | One of: `powershell`, `python`, `terraform`, `shell` |

### Body

Multipart form data with a file field named `file`.

### Example Request (curl)

```bash
curl -X POST "http://nexus:8080/api/scripts/powershell" -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIs..." -F "file=@./Deploy.ps1"
```

## Response

### Success (200)

```json
{
  "success": true,
  "message": "Script uploaded successfully"
}
```

### Error (4xx)

| Status | Body                                                  |
|--------|-------------------------------------------------------|
| 401    | `{ "success": false, "message": "Unauthorized" }`    |
| 400    | `{ "success": false, "message": "No file provided" }` |

## Notes

- The file is uploaded to the `nexus-{type}` blob container.
