# Save Configuration

Persists updated configuration values to the server.

## Request

`POST /api/config`

### Headers

| Header          | Value              | Required |
|-----------------|--------------------|----------|
| `Authorization` | `Bearer <token>`   | Yes      |
| `Content-Type`  | `application/json` | Yes      |

### Body

| Field                 | Type    | Required | Description                                |
|-----------------------|---------|----------|--------------------------------------------|
| `storageAccount`      | string  | Yes      | Azure Storage account name                 |
| `key`                 | string  | Yes      | Azure Storage account key                  |
| `resourceGroup`       | string  | Yes      | Azure resource group name                  |
| `logRetentionEnabled` | boolean | No       | Whether automatic log retention is enabled |
| `logRetentionDays`    | integer | No       | Number of days to retain logs              |

### Example Request (curl)

```bash
curl -X POST http://nexus:8080/api/config \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..." \
  -H "Content-Type: application/json" \
  -d '{"storageAccount":"nexusstorage","key":"abc123...","resourceGroup":"rg-nexus-prod","logRetentionEnabled":true,"logRetentionDays":30}'
```

## Response

### Success (200)

```json
{
  "success": true,
  "message": "Configuration saved successfully"
}
```

### Error (4xx)

| Status | Body                                        |
|--------|---------------------------------------------|
| 400    | `{ "error": "Missing required fields" }`    |
| 401    | `{ "error": "Authentication required" }`    |

## Notes

- `storageAccount`, `key`, and `resourceGroup` are required in every request; omitting any of them returns a 400 error.
