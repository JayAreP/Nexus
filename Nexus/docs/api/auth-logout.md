# Logout

Invalidate the current session token.

## Request

`POST /api/auth/logout`

### Headers

| Header | Value |
|--------|-------|
| Authorization | Bearer {token} |

### Body

No body required.

### Example Request

```bash
curl -X POST http://nexus:8080/api/auth/logout -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VybmFtZSI6ImFkbWluIn0.abc123"
```

## Response

### Success (200)

```json
{
  "success": true
}
```

### Error (401)

```json
{
  "success": false,
  "error": "Invalid or expired token"
}
```

## Notes

- Invalidates the token used in the request. Subsequent requests with the same token will be rejected.
