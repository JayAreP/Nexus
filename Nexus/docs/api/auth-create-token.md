# Create API Token

Generate a new API token.

## Request

`POST /api/auth/tokens`

### Headers

| Header | Value |
|--------|-------|
| Authorization | Bearer {token} |
| Content-Type | application/json |

### Body

| Name | Type | Required | Description |
|------|------|----------|-------------|
| name | string | Yes | A descriptive name for the token |

### Example Request

```bash
curl -X POST http://nexus:8080/api/auth/tokens -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VybmFtZSI6ImFkbWluIn0.abc123" -H "Content-Type: application/json" -d '{"name": "CI Pipeline"}'
```

## Response

### Success (200)

```json
{
  "success": true,
  "id": "a1b2c3d4",
  "name": "CI Pipeline",
  "token": "nxs_4f8a2b1c9d3e7f6a0b5c8d2e1f4a7b3c9d6e0f2a5b8c1d4e7f0a3b6c9d2ex7f2",
  "message": "Store this token securely. It will not be shown again."
}
```

### Error (400)

```json
{
  "success": false,
  "error": "Token name is required"
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
- The full token value is returned only at creation time. It cannot be retrieved again afterward.
- API tokens are permanent and do not expire.
