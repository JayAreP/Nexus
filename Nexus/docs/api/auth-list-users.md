# List Users

Retrieve all registered users.

## Request

`GET /api/auth/users`

### Headers

| Header | Value |
|--------|-------|
| Authorization | Bearer {token} |

### Parameters

No parameters.

### Example Request

```bash
curl http://nexus:8080/api/auth/users -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VybmFtZSI6ImFkbWluIn0.abc123"
```

## Response

### Success (200)

```json
{
  "success": true,
  "users": [
    {
      "username": "admin",
      "role": "admin",
      "createdAt": "2026-01-15T10:00:00.000Z"
    },
    {
      "username": "jdoe",
      "role": "user",
      "createdAt": "2026-02-20T14:30:00.000Z"
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

- Requires admin role. Non-admin users will receive a 403 response.
