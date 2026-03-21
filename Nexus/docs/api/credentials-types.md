# List Credential Types

Returns all supported credential types and their field definitions.

## Request

`GET /api/credentials/types`

### Headers

| Header          | Value            | Required |
|-----------------|------------------|----------|
| `Authorization` | `Bearer <token>` | Yes      |

### Parameters

None.

### Example Request (curl)

```bash
curl -s -X GET http://nexus:8080/api/credentials/types -H "Authorization: Bearer <token>"
```

## Response

### Success (200)

```json
{
  "success": true,
  "types": {
    "usernamepassword": {
      "label": "Username & Password",
      "fields": [
        { "name": "username", "label": "Username", "type": "text", "secret": false },
        { "name": "password", "label": "Password", "type": "password", "secret": true }
      ]
    },
    "azureserviceprincipal": {
      "label": "Azure Service Principal",
      "fields": [
        { "name": "tenantId", "label": "Tenant ID", "type": "text", "secret": false },
        { "name": "clientId", "label": "Client ID", "type": "text", "secret": false },
        { "name": "clientSecret", "label": "Client Secret", "type": "password", "secret": true }
      ]
    },
    "apikey": {
      "label": "API Key",
      "fields": [
        { "name": "key", "label": "API Key", "type": "password", "secret": true }
      ]
    },
    "oauth2": {
      "label": "OAuth2",
      "fields": [
        { "name": "clientId", "label": "Client ID", "type": "text", "secret": false },
        { "name": "clientSecret", "label": "Client Secret", "type": "password", "secret": true },
        { "name": "tokenUrl", "label": "Token URL", "type": "text", "secret": false },
        { "name": "scope", "label": "Scope", "type": "text", "secret": false }
      ]
    },
    "aws": {
      "label": "AWS Credentials",
      "fields": [
        { "name": "accessKeyId", "label": "Access Key ID", "type": "text", "secret": false },
        { "name": "secretAccessKey", "label": "Secret Access Key", "type": "password", "secret": true },
        { "name": "region", "label": "Region", "type": "text", "secret": false }
      ]
    },
    "gcp": {
      "label": "GCP Credentials",
      "fields": [
        { "name": "projectId", "label": "Project ID", "type": "text", "secret": false },
        { "name": "serviceAccountKey", "label": "Service Account Key (JSON)", "type": "textarea", "secret": true }
      ]
    },
    "connectionstring": {
      "label": "Connection String",
      "fields": [
        { "name": "connectionString", "label": "Connection String", "type": "password", "secret": true }
      ]
    },
    "token": {
      "label": "Token",
      "fields": [
        { "name": "token", "label": "Token", "type": "password", "secret": true }
      ]
    }
  }
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
- Each credential type defines its fields with a `name`, `label`, `type`, and `secret` boolean.
- Fields marked `secret: true` are encrypted at rest and masked when retrieved via the GET endpoint.
