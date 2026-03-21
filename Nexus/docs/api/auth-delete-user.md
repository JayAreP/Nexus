# Delete User

Delete an existing user account.

## Request

`DELETE /api/auth/users/:username`

### Headers

| Header | Value |
|--------|-------|
| Authorization | Bearer {token} |

### Parameters

| Name | In | Type | Required | Description |
|------|-----|------|----------|-------------|
| username | URL | string | Yes | The username of the user to delete |

### Example Request

```bash
curl -X DELETE http://nexus:8080/api/auth/users/jdoe -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VybmFtZSI6ImFkbWluIn0.abc123"
```

## Response

### Success (200)

```json
{
  "success": true,
  "message": "User 'jdoe' deleted"
}
```

### Error (400)

```json
{
  "success": false,
  "error": "Cannot delete your own account"
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
- An admin cannot delete their own account.
- Deleting a user also removes all of their active sessions and API tokens.
