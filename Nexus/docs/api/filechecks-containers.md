# List File Check Containers

Lists all blob containers on the file check's storage account.

## Request

`GET /api/filechecks/:name/containers`

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
curl -s -X GET http://nexus:8080/api/filechecks/prod-storage/containers -H "Authorization: Bearer <token>"
```

## Response

### Success (200)

```json
{
  "success": true,
  "containers": [
    { "name": "raw-data" },
    { "name": "processed" },
    { "name": "archives" }
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
- Lists containers on the Azure storage account associated with the named file check.
- The file check's configured credentials (SAS token or Azure auth) are used to connect to the storage account.
