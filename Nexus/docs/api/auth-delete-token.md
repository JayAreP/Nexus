# Delete API Token

Revoke and delete an API token.

## Request

`DELETE /api/auth/tokens/:id`

### Headers

| Header | Value |
|--------|-------|
| Authorization | Bearer {token} |

### Parameters

| Name | In | Type | Required | Description |
|------|-----|------|----------|-------------|
| id | URL | string | Yes | The ID of the token to delete |

### Example Request

```bash
curl -X DELETE http://nexus:8080/api/auth/tokens/a1b2c3d4 -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VybmFtZSI6ImFkbWluIn0.abc123"
```

## Response

### Success (200)

```json
{
  "success": true,
  "message": "API token deleted"
}
```

### Error (403)

```json
{
  "success": false,
  "error": "Admin access required"
}
```

### Error (404)

```json
{
  "success": false,
  "error": "Token not found"
}
```

## Notes

- Requires admin role.
- Once deleted, any requests using the revoked token will be rejected.
