# Update User

Update an existing user's password or role.

## Request

`PUT /api/auth/users/:username`

### Headers

| Header | Value |
|--------|-------|
| Authorization | Bearer {token} |
| Content-Type | application/json |

### Parameters

| Name | In | Type | Required | Description |
|------|-----|------|----------|-------------|
| username | URL | string | Yes | The username of the user to update |

### Body

| Name | Type | Required | Description |
|------|------|----------|-------------|
| password | string | No | New password for the user |
| role | string | No | New role for the user |

### Example Request

```bash
curl -X PUT http://nexus:8080/api/auth/users/jdoe -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VybmFtZSI6ImFkbWluIn0.abc123" -H "Content-Type: application/json" -d '{"role": "admin"}'
```

## Response

### Success (200)

```json
{
  "success": true,
  "message": "User 'jdoe' updated"
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
  "error": "User not found"
}
```

## Notes

- Requires admin role.
- At least one of `password` or `role` should be provided.
