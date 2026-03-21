# Delete Module

Removes an installed PowerShell module by name.

## Request

`DELETE /api/modules/:name`

### Headers

| Header          | Value            | Required |
|-----------------|------------------|----------|
| Authorization   | Bearer {token}   | Yes      |

### Parameters / Body

| Parameter | Location | Type   | Required | Description              |
|-----------|----------|--------|----------|--------------------------|
| name      | URL      | string | Yes      | Module name to remove    |

### Example Request (curl)

```bash
curl -X DELETE http://nexus:8080/api/modules/PSScriptAnalyzer -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

## Response

### Success (200)

```json
{
  "success": true,
  "message": "Removed PSScriptAnalyzer"
}
```

### Error (400)

```json
{
  "success": false,
  "error": "Invalid module name"
}
```

### Error (404)

```json
{
  "success": false,
  "error": "Module not found"
}
```

## Notes

- Removes the module from all `PSModulePath` entries where it exists.
- Module name is validated against alphanumeric characters, dots, hyphens, and underscores only.
