# Save Credential

Creates or updates a credential.

## Request

`POST /api/credentials`

### Headers

| Header          | Value              | Required |
|-----------------|--------------------|----------|
| `Authorization` | `Bearer <token>`   | Yes      |
| `Content-Type`  | `application/json` | Yes      |

### Body

| Field         | Type   | Required | Description                                  |
|---------------|--------|----------|----------------------------------------------|
| `name`        | string | Yes      | Unique name for the credential               |
| `type`        | string | Yes      | Credential type (see `/api/credentials/types`)|
| `description` | string | No       | Optional description                         |
| `values`      | object | Yes      | Key-value pairs matching the type's fields   |

### Example Request (curl)

```bash
curl -s -X POST http://nexus:8080/api/credentials -H "Authorization: Bearer <token>" -H "Content-Type: application/json" -d '{"name": "prod-db", "type": "usernamepassword", "description": "Production database credentials", "values": {"username": "admin", "password": "s3cureP@ss!"}}'
```

## Response

### Success (200)

```json
{
  "success": true,
  "message": "Credential saved successfully"
}
```

### Error (400)

```json
{
  "success": false,
  "message": "Name and type are required"
}
```

```json
{
  "success": false,
  "message": "Name contains invalid characters"
}
```

## Notes

- Authentication is required.
- The `name` field must not contain invalid characters (e.g., slashes, special symbols).
- Secret fields are automatically encrypted with AES before being stored.
- If a credential with the same name already exists, it will be updated.
