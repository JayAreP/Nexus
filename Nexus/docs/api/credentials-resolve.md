# Resolve Credential

Returns a credential with all secret fields fully decrypted.

## Request

`GET /api/credentials/:name/resolve`

### Headers

| Header          | Value            | Required |
|-----------------|------------------|----------|
| `Authorization` | `Bearer <token>` | Yes      |

### Parameters

| Parameter | Location | Required | Description              |
|-----------|----------|----------|--------------------------|
| `name`    | Path     | Yes      | Name of the credential   |

### Example Request (curl)

```bash
curl -s -X GET http://nexus:8080/api/credentials/prod-db/resolve -H "Authorization: Bearer <token>"
```

## Response

### Success (200)

```json
{
  "success": true,
  "credential": {
    "name": "prod-db",
    "type": "usernamepassword",
    "values": {
      "username": "admin",
      "password": "actual-decrypted-value"
    }
  }
}
```

### Error (404)

```json
{
  "success": false,
  "message": "Credential not found"
}
```

## Notes

- Authentication is required.
- Unlike the standard GET endpoint, this returns fully decrypted secret values.
- Intended for script and automation consumption where actual credential values are needed.
- Use with caution; decrypted secrets are transmitted in the response body.
