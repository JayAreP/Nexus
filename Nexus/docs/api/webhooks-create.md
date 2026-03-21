# Create Webhook

Creates a new webhook configuration.

## Request

`POST /api/webhooks`

### Headers

| Header          | Value              | Required |
|-----------------|--------------------|----------|
| `Authorization` | `Bearer <token>`   | Yes      |
| `Content-Type`  | `application/json` | Yes      |

### Body

| Field          | Type   | Required | Description                          |
|----------------|--------|----------|--------------------------------------|
| `name`         | string | Yes      | Unique name for the webhook          |
| `uri`          | string | Yes      | Destination URL                      |
| `authType`     | string | No       | `"none"` (default) or `"azure_sp"`   |
| `tenantId`     | string | No       | Azure AD tenant ID (for `azure_sp`)  |
| `clientId`     | string | No       | Azure AD client ID (for `azure_sp`)  |
| `clientSecret` | string | No       | Azure AD client secret (for `azure_sp`) |

### Example Request (curl)

```bash
curl -s -X POST http://nexus:8080/api/webhooks -H "Authorization: Bearer <token>" -H "Content-Type: application/json" -d '{"name": "deploy-notification", "uri": "https://example.com/hook", "authType": "none"}'
```

With Azure Service Principal auth:

```bash
curl -s -X POST http://nexus:8080/api/webhooks -H "Authorization: Bearer <token>" -H "Content-Type: application/json" -d '{"name": "azure-webhook", "uri": "https://myapp.azurewebsites.net/api/trigger", "authType": "azure_sp", "tenantId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", "clientId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", "clientSecret": "my-client-secret"}'
```

## Response

### Success (200)

```json
{
  "success": true,
  "message": "Webhook created successfully"
}
```

### Error (400)

```json
{
  "success": false,
  "message": "Name and URI are required"
}
```

## Notes

- Authentication is required.
- Both `name` and `uri` are required fields.
- When `authType` is `"azure_sp"`, the `tenantId`, `clientId`, and `clientSecret` fields should be provided.
