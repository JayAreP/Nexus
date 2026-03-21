# Get File Check

Returns the full configuration for a single file check.

## Request

`GET /api/filechecks/:name`

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
curl -s -X GET http://nexus:8080/api/filechecks/prod-storage -H "Authorization: Bearer <token>"
```

## Response

### Success (200)

```json
{
  "success": true,
  "filecheck": {
    "name": "prod-storage",
    "storageAccount": "mystorageaccount",
    "authType": "sas",
    "sasToken": "sv=2022-11-02&ss=b&srt=sco&sp=rl&se=2026-12-31T00:00:00Z&sig=xxxxx"
  }
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
- Returns the complete file check configuration including the SAS token if applicable.
