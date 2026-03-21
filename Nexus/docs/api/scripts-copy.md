# Copy Script

Creates a copy of an existing script under a new name within the same type container.

## Request

`POST /api/scripts/:type/:name/copy`

### Headers

| Header          | Value              | Required |
|-----------------|--------------------|----------|
| Authorization   | Bearer {token}     | Yes      |
| Content-Type    | application/json   | Yes      |

### Parameters

| Parameter | In   | Type   | Required | Description                                          |
|-----------|------|--------|----------|------------------------------------------------------|
| type      | path | string | Yes      | One of: `powershell`, `python`, `terraform`, `shell` |
| name      | path | string | Yes      | Source script filename (e.g. `Deploy.ps1`)           |

### Body

```json
{
  "newName": "Deploy-v2.ps1"
}
```

| Field   | Type   | Required | Description                          |
|---------|--------|----------|--------------------------------------|
| newName | string | Yes      | Filename for the copied script       |

### Example Request (curl)

```bash
curl -X POST "http://nexus:8080/api/scripts/powershell/Deploy.ps1/copy" -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIs..." -H "Content-Type: application/json" -d '{"newName": "Deploy-v2.ps1"}'
```

## Response

### Success (200)

```json
{
  "success": true,
  "message": "Script copied"
}
```

### Error (4xx)

| Status | Body                                                        |
|--------|-------------------------------------------------------------|
| 400    | `{ "success": false, "message": "newName is required" }`   |
| 401    | `{ "success": false, "message": "Unauthorized" }`          |
| 404    | `{ "success": false, "message": "Source script not found" }` |

## Notes

- The copy is created in the same `nexus-{type}` container as the source script.
