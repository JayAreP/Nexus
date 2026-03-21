# Get Credential

Returns a single credential by name with secret fields masked.

## Request

`GET /api/credentials/:name`

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
curl -s -X GET http://nexus:8080/api/credentials/prod-db -H "Authorization: Bearer <token>"
```

## Response

### Success (200)

```json
{
  "success": true,
  "credential": {
    "name": "prod-db",
    "type": "usernamepassword",
    "description": "Production database credentials",
    "created": "2026-01-15T08:30:00.000Z",
    "modified": "2026-03-10T14:22:00.000Z",
    "values": {
      "username": "admin",
      "password": "********"
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
- Secret fields are masked with `"********"` in the response.
- To retrieve fully decrypted values, use the [resolve endpoint](credentials-resolve.md).
