# Copy File Check

Creates a duplicate of an existing file check under a new name.

## Request

`POST /api/filechecks/:name/copy`

### Headers

| Header          | Value              | Required |
|-----------------|--------------------|----------|
| `Authorization` | `Bearer <token>`   | Yes      |
| `Content-Type`  | `application/json` | Yes      |

### Parameters

| Parameter | Location | Required | Description                       |
|-----------|----------|----------|-----------------------------------|
| `name`    | Path     | Yes      | Name of the file check to copy    |

### Body

| Field     | Type   | Required | Description                     |
|-----------|--------|----------|---------------------------------|
| `newName` | string | Yes      | Name for the copied file check  |

### Example Request (curl)

```bash
curl -s -X POST http://nexus:8080/api/filechecks/prod-storage/copy -H "Authorization: Bearer <token>" -H "Content-Type: application/json" -d '{"newName": "prod-storage-backup"}'
```

## Response

### Success (200)

```json
{
  "success": true,
  "message": "File check copied successfully"
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
  "message": "File check not found"
}
```

## Notes

- Authentication is required.
- The new file check is an independent copy; changes to either do not affect the other.
