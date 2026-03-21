# Create User

Create a new user account.

## Request

`POST /api/auth/users`

### Headers

| Header | Value |
|--------|-------|
| Authorization | Bearer {token} |
| Content-Type | application/json |

### Body

| Name | Type | Required | Description |
|------|------|----------|-------------|
| username | string | Yes | The new user's username |
| password | string | Yes | The new user's password |
| role | string | No | The user's role. Defaults to `"user"` |

### Example Request

```bash
curl -X POST http://nexus:8080/api/auth/users -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VybmFtZSI6ImFkbWluIn0.abc123" -H "Content-Type: application/json" -d '{"username": "jdoe", "password": "n3wP@ssw0rd", "role": "user"}'
```

## Response

### Success (200)

```json
{
  "success": true,
  "message": "User 'jdoe' created"
}
```

### Error (400)

```json
{
  "success": false,
  "error": "Username and password are required"
}
```

### Error (403)

```json
{
  "success": false,
  "error": "Admin access required"
}
```

### Error (409)

```json
{
  "success": false,
  "error": "User 'jdoe' already exists"
}
```

## Notes

- Requires admin role.
- If `role` is omitted, it defaults to `"user"`.
