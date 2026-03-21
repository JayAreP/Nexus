# Install Module

Installs a module of the specified type (PowerShell, Python, or APT).

## Request

`POST /api/modules/:type`

### Headers

| Header          | Value              | Required |
|-----------------|--------------------|----------|
| Authorization   | Bearer {token}     | Yes      |
| Content-Type    | application/json   | Yes      |

### Parameters / Body

| Parameter | Location | Type   | Required | Description                                |
|-----------|----------|--------|----------|--------------------------------------------|
| type      | URL      | string | Yes      | One of: `powershell`, `python`, or `apt`   |
| name      | Body     | string | Yes      | Module/package name to install             |

### Example Request (curl)

```bash
curl -X POST http://nexus:8080/api/modules/powershell -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..." -H "Content-Type: application/json" -d '{"name":"PSScriptAnalyzer"}'
```

## Response

### Success (200)

```json
{
  "success": true,
  "message": "Installed PSScriptAnalyzer"
}
```

### Error (400)

```json
{
  "success": false,
  "error": "Invalid module name"
}
```

### Error (500)

```json
{
  "success": false,
  "error": "Install failed: could not resolve module PSScriptAnalyzer"
}
```

## Notes

- Module name is validated against alphanumeric characters, dots, hyphens, and underscores only.
- PowerShell modules install to `/mnt/nexus/ps-modules`.
- Python packages install to `/mnt/nexus/py-packages`.
- APT packages install via `apt-get`.
