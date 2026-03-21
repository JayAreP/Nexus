# Install Module from GitHub

Clones a GitHub repository and installs it as a PowerShell module.

## Request

`POST /api/modules/github`

### Headers

| Header          | Value              | Required |
|-----------------|--------------------|----------|
| Authorization   | Bearer {token}     | Yes      |
| Content-Type    | application/json   | Yes      |

### Parameters / Body

| Field | Type   | Required | Description                                    |
|-------|--------|----------|------------------------------------------------|
| url   | string | Yes      | GitHub repository URL (e.g. `https://github.com/owner/repo`) |

### Example Request (curl)

```bash
curl -X POST http://nexus:8080/api/modules/github -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..." -H "Content-Type: application/json" -d '{"url":"https://github.com/PowerShell/PSScriptAnalyzer"}'
```

## Response

### Success (200)

```json
{
  "success": true,
  "message": "Installed PSScriptAnalyzer v1.21.0 from GitHub"
}
```

### Error (400)

```json
{
  "success": false,
  "error": "Invalid GitHub URL"
}
```

### Error (500)

```json
{
  "success": false,
  "error": "Clone failed: repository not found"
}
```

## Notes

- The repository is cloned with `--depth=1` for efficiency.
- The installer searches the cloned repo for a `.psd1` manifest file to determine the module name and version.
- The module is installed to `/usr/local/share/powershell/Modules/{name}/{version}`.
- The temporary clone is cleaned up after installation.
