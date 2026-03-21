# Get Configuration

Returns the current server configuration values.

## Request

`GET /api/config`

### Headers

| Header          | Value              | Required |
|-----------------|--------------------|----------|
| `Authorization` | `Bearer <token>`   | Yes      |

### Parameters

None.

### Example Request (curl)

```bash
curl http://nexus:8080/api/config \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

## Response

### Success (200)

```json
{
  "success": true,
  "storageAccount": "nexusstorage",
  "key": "abc123...",
  "resourceGroup": "rg-nexus-prod",
  "logRetentionEnabled": true,
  "logRetentionDays": 30
}
```

| Field                 | Type    | Description                                |
|-----------------------|---------|--------------------------------------------|
| `storageAccount`      | string  | Azure Storage account name                 |
| `key`                 | string  | Azure Storage account key                  |
| `resourceGroup`       | string  | Azure resource group name                  |
| `logRetentionEnabled` | boolean | Whether automatic log retention is enabled |
| `logRetentionDays`    | integer | Number of days to retain logs              |

### Error (4xx)

| Status | Body                                        |
|--------|---------------------------------------------|
| 401    | `{ "error": "Authentication required" }`    |

## Notes

- All fields are returned regardless of whether they have been explicitly set.
