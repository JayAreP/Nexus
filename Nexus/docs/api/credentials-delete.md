# Delete Credential

Deletes a credential by name.

## Request

`DELETE /api/credentials/:name`

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
curl -s -X DELETE http://nexus:8080/api/credentials/prod-db -H "Authorization: Bearer <token>"
```

## Response

### Success (200)

```json
{
  "success": true,
  "message": "Credential deleted successfully"
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
