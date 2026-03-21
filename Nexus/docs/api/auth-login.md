# Login

Authenticate a user and receive a session token.

## Request

`POST /api/auth/login`

### Headers

| Header | Value |
|--------|-------|
| Content-Type | application/json |

### Body

| Name | Type | Required | Description |
|------|------|----------|-------------|
| username | string | Yes | The user's username |
| password | string | Yes | The user's password |

### Example Request

```bash
curl -X POST http://nexus:8080/api/auth/login -H "Content-Type: application/json" -d '{"username": "admin", "password": "s3cureP@ss"}'
```

## Response

### Success (200)

```json
{
  "success": true,
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VybmFtZSI6ImFkbWluIiwicm9sZSI6ImFkbWluIn0.abc123",
  "username": "admin",
  "role": "admin",
  "expiresAt": "2026-03-22T02:30:00.000Z"
}
```

### Error (400)

```json
{
  "success": false,
  "error": "Username and password are required"
}
```

### Error (401)

```json
{
  "success": false,
  "error": "Invalid credentials"
}
```

## Notes

- No authentication is required for this endpoint.
- The returned session token is valid for 8 hours from the time of issuance.
