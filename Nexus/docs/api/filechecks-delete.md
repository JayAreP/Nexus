# Delete File Check

Deletes a file check by name.

## Request

`DELETE /api/filechecks/:name`

### Headers

| Header          | Value            | Required |
|-----------------|------------------|----------|
| `Authorization` | `Bearer <token>` | Yes      |

### Parameters

| Parameter | Location | Required | Description             |
|-----------|----------|----------|-------------------------|
| `name`    | Path     | Yes      | Name of the file check  |

### Example Request (curl)

```bash
curl -s -X DELETE http://nexus:8080/api/filechecks/prod-storage -H "Authorization: Bearer <token>"
```

## Response

### Success (200)

```json
{
  "success": true,
  "message": "File check deleted successfully"
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
