# Prepare Storage

Creates all required `nexus-*` storage containers in the configured Azure Storage account.

## Request

`POST /api/config/prepare`

### Headers

| Header          | Value              | Required |
|-----------------|--------------------|----------|
| `Authorization` | `Bearer <token>`   | Yes      |

### Body

No body required.

### Example Request (curl)

```bash
curl -X POST http://nexus:8080/api/config/prepare \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

## Response

### Success (200)

```json
{
  "success": true,
  "message": "Storage containers prepared successfully"
}
```

### Error (4xx)

| Status | Body                                        |
|--------|---------------------------------------------|
| 401    | `{ "error": "Authentication required" }`    |
| 400    | `{ "error": "Storage account not configured" }` |

## Notes

- Creates the following containers if they do not already exist:
  - `nexus-config`
  - `nexus-powershell`
  - `nexus-terraform`
  - `nexus-python`
  - `nexus-shell`
  - `nexus-webhooks`
  - `nexus-credentials`
- Requires a valid storage account configuration (see [Save Configuration](config-save.md)) before this endpoint can succeed.
