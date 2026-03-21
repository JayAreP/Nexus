# List API Tokens

Retrieve all API tokens.

## Request

`GET /api/auth/tokens`

### Headers

| Header | Value |
|--------|-------|
| Authorization | Bearer {token} |

### Parameters

No parameters.

### Example Request

```bash
curl http://nexus:8080/api/auth/tokens -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VybmFtZSI6ImFkbWluIn0.abc123"
```

## Response

### Success (200)

```json
{
  "success": true,
  "tokens": [
    {
      "id": "a1b2c3d4",
      "name": "CI Pipeline",
      "createdBy": "admin",
      "createdAt": "2026-02-10T08:00:00.000Z",
      "tokenPreview": "nxs_...x7f2"
    },
    {
      "id": "e5f6g7h8",
      "name": "Monitoring",
      "createdBy": "admin",
      "createdAt": "2026-03-01T12:00:00.000Z",
      "tokenPreview": "nxs_...k9m1"
    }
  ]
}
```

### Error (403)

```json
{
  "success": false,
  "error": "Admin access required"
}
```

## Notes

- Requires admin role.
- The full token value is never returned in listings. Only a truncated preview is provided.
