# List Modules

Returns installed modules for a given type: PowerShell, Python, or APT.

## Request

`GET /api/modules/:type`

### Headers

| Header          | Value            | Required |
|-----------------|------------------|----------|
| Authorization   | Bearer {token}   | Yes      |

### Parameters / Body

| Parameter | Location | Type   | Required | Description                                |
|-----------|----------|--------|----------|--------------------------------------------|
| type      | URL      | string | Yes      | One of: `powershell`, `python`, or `apt`   |

### Example Request (curl)

```bash
curl -X GET http://nexus:8080/api/modules/powershell -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

## Response

### Success (200) -- PowerShell

```json
{
  "success": true,
  "modules": [
    {
      "name": "Az.Accounts",
      "version": "2.12.1",
      "path": "/mnt/nexus/ps-modules/Az.Accounts/2.12.1"
    },
    {
      "name": "PSScriptAnalyzer",
      "version": "1.21.0",
      "path": "/mnt/nexus/ps-modules/PSScriptAnalyzer/1.21.0"
    }
  ]
}
```

### Success (200) -- Python

```json
{
  "success": true,
  "output": "Package    Version\n---------- -------\nrequests   2.31.0\nboto3      1.28.0\npip        23.2.1"
}
```

### Success (200) -- APT

```json
{
  "success": true,
  "packages": [
    {
      "name": "jq",
      "version": "1.6-2.1",
      "note": "JSON processor",
      "source": "apt",
      "installed": true
    },
    {
      "name": "curl",
      "version": "7.88.1-10",
      "note": "HTTP client",
      "source": "apt",
      "installed": true
    }
  ]
}
```

### Error (4xx)

```json
{
  "success": false,
  "error": "Unauthorized"
}
```

## Notes

- Response shape varies by module type.
- PowerShell modules return structured objects with name, version, and path.
- Python modules return raw `pip list` output as a string.
- APT packages return structured objects with install status.
