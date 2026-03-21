# Get Script Parameters

Returns auto-parsed parameter definitions extracted from a script's source.

## Request

`GET /api/scripts/:type/:name/parameters`

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
curl -X GET "http://nexus:8080/api/scripts/powershell/Deploy.ps1/parameters" -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIs..."
```

## Response

### Success (200)

```json
{
  "success": true,
  "parameters": [
    {
      "name": "Name",
      "type": "string",
      "required": true
    },
    {
      "name": "Count",
      "type": "int",
      "required": false,
      "default": 1
    }
  ]
}
```

### Error (4xx)

| Status | Body                                                     |
|--------|----------------------------------------------------------|
| 401    | `{ "success": false, "message": "Unauthorized" }`       |
| 404    | `{ "success": false, "message": "Script not found" }`   |

## Notes

- Introspects the script's `param` block to extract parameter names and types.
- The parsing logic is language-aware; for PowerShell it reads the `param()` block, for Python it inspects `argparse` or function signatures, etc.
