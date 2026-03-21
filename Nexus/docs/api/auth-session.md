# Get Session

Retrieve the current user's session information.

## Request

`GET /api/auth/session`

### Headers

| Header | Value |
|--------|-------|
| Authorization | Bearer {token} |

### Parameters

No parameters.

### Example Request

```bash
curl http://nexus:8080/api/auth/session -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VybmFtZSI6ImFkbWluIn0.abc123"
```

## Response

### Success (200)

```json
{
  "success": true,
  "username": "admin",
  "role": "admin"
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

- Useful for validating a stored token and retrieving the associated user info on application startup.
