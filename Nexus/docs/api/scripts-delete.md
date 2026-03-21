# Delete Script

Deletes a script from the type-specific storage container.

## Request

`DELETE /api/scripts/:type/:name`

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
curl -X DELETE "http://nexus:8080/api/scripts/powershell/Deploy.ps1" -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIs..."
```

## Response

### Success (200)

```json
{
  "success": true,
  "message": "Script deleted"
}
```

### Error (4xx)

| Status | Body                                                     |
|--------|----------------------------------------------------------|
| 401    | `{ "success": false, "message": "Unauthorized" }`       |
| 404    | `{ "success": false, "message": "Script not found" }`   |

## Notes

- This action is irreversible. The script blob is permanently removed from the `nexus-{type}` container.
