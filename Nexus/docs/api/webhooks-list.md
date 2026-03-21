# List Webhooks

Returns all configured webhooks.

## Request

`GET /api/webhooks`

### Headers

| Header          | Value            | Required |
|-----------------|------------------|----------|
| `Authorization` | `Bearer <token>` | Yes      |

### Parameters

None.

### Example Request (curl)

```bash
curl -s -X GET http://nexus:8080/api/webhooks -H "Authorization: Bearer <token>"
```

## Response

### Success (200)

```json
{
  "success": true,
  "webhooks": [
    {
      "name": "deploy-notification",
      "uri": "https://example.com/hook",
      "authType": "none"
    },
    {
      "name": "azure-webhook",
      "uri": "https://myapp.azurewebsites.net/api/trigger",
      "authType": "azure_sp"
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
- Returns an array of all webhooks with their name, URI, and auth type.
