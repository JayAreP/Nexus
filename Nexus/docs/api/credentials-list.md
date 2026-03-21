# List Credentials

Returns metadata for all stored credentials.

## Request

`GET /api/credentials`

### Headers

| Header          | Value            | Required |
|-----------------|------------------|----------|
| `Authorization` | `Bearer <token>` | Yes      |

### Parameters

None.

### Example Request (curl)

```bash
curl -s -X GET http://nexus:8080/api/credentials -H "Authorization: Bearer <token>"
```

## Response

### Success (200)

```json
{
  "success": true,
  "credentials": [
    {
      "name": "prod-db",
      "type": "usernamepassword",
      "description": "Production database credentials",
      "created": "2026-01-15T08:30:00.000Z",
      "modified": "2026-03-10T14:22:00.000Z"
    },
    {
      "name": "azure-sp-deploy",
      "type": "azureserviceprincipal",
      "description": "Deployment service principal",
      "created": "2026-02-01T10:00:00.000Z",
      "modified": "2026-02-01T10:00:00.000Z"
    }
  ]
}
```

### Error (401)

```json
{
  "success": false,
  "message": "Unauthorized"
}
```

## Notes

- Authentication is required.
- Returns metadata only; no secret values are included in the response.
