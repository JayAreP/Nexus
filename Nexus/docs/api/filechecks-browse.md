# Browse File Check Container

Browses folders and files within a container on the file check's storage account.

## Request

`GET /api/filechecks/:name/browse`

### Headers

| Header          | Value            | Required |
|-----------------|------------------|----------|
| `Authorization` | `Bearer <token>` | Yes      |

### Parameters

| Parameter   | Location | Required | Description                              |
|-------------|----------|----------|------------------------------------------|
| `name`      | Path     | Yes      | Name of the file check                   |
| `container` | Query    | Yes      | Container name to browse                 |
| `prefix`    | Query    | No       | Folder prefix to filter results          |

### Example Request (curl)

Browse the root of a container:

```bash
curl -s -X GET "http://nexus:8080/api/filechecks/prod-storage/browse?container=raw-data" -H "Authorization: Bearer <token>"
```

Browse a subfolder:

```bash
curl -s -X GET "http://nexus:8080/api/filechecks/prod-storage/browse?container=raw-data&prefix=2026/03/" -H "Authorization: Bearer <token>"
```

## Response

### Success (200)

```json
{
  "success": true,
  "folders": [
    { "name": "2026/", "prefix": "2026/" },
    { "name": "backups/", "prefix": "backups/" }
  ],
  "files": [
    { "name": "readme.txt", "fullPath": "readme.txt", "size": 1024 },
    { "name": "config.json", "fullPath": "config.json", "size": 512 }
  ],
  "prefix": ""
}
```

### Error (400)

```json
{
  "success": false,
  "message": "Container is required"
}
```

## Notes

- Authentication is required.
- The `container` query parameter is required.
- When `prefix` is provided, results are scoped to that folder path within the container.
- Folders are virtual prefixes in blob storage, not physical directories.
