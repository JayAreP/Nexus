# Get Webhook

Returns the full configuration for a single webhook.

## Request

`GET /api/webhooks/:name`

### Headers

| Header          | Value            | Required |
|-----------------|------------------|----------|
| `Authorization` | `Bearer <token>` | Yes      |

### Parameters

| Parameter | Location | Required | Description          |
|-----------|----------|----------|----------------------|
| `name`    | Path     | Yes      | Name of the webhook  |

### Example Request (curl)

```bash
curl -s -X GET http://nexus:8080/api/webhooks/azure-webhook -H "Authorization: Bearer <token>"
```

## Response

### Success (200)

```json
{
  "success": true,
  "webhook": {
    "name": "azure-webhook",
    "uri": "https://myapp.azurewebsites.net/api/trigger",
    "authType": "azure_sp",
    "tenantId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    "clientId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    "clientSecret": "my-client-secret"
  }
}
```

### Error (404)

```json
{
  "success": false,
  "message": "Webhook not found"
}
```

## Notes

- Authentication is required.
- Returns the complete webhook configuration including auth credentials.
