# Copy Credential

Creates a duplicate of an existing credential under a new name.

## Request

`POST /api/credentials/:name/copy`

### Headers

| Header          | Value              | Required |
|-----------------|--------------------|----------|
| `Authorization` | `Bearer <token>`   | Yes      |
| `Content-Type`  | `application/json` | Yes      |

### Parameters

| Parameter | Location | Required | Description                      |
|-----------|----------|----------|----------------------------------|
| `name`    | Path     | Yes      | Name of the credential to copy   |

### Body

| Field     | Type   | Required | Description                    |
|-----------|--------|----------|--------------------------------|
| `newName` | string | Yes      | Name for the copied credential |

### Example Request (curl)

```bash
curl -s -X POST http://nexus:8080/api/credentials/prod-db/copy -H "Authorization: Bearer <token>" -H "Content-Type: application/json" -d '{"newName": "staging-db"}'
```

## Response

### Success (200)

```json
{
  "success": true,
  "message": "Credential copied successfully"
}
```

### Error (400)

```json
{
  "success": false,
  "message": "New name is required"
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
- The new credential is an independent copy; changes to either do not affect the other.
- Encrypted secret values are preserved in the copy.
