# List File Checks

Returns all configured file checks.

## Request

`GET /api/filechecks`

### Headers

| Header          | Value            | Required |
|-----------------|------------------|----------|
| `Authorization` | `Bearer <token>` | Yes      |

### Parameters

None.

### Example Request (curl)

```bash
curl -s -X GET http://nexus:8080/api/filechecks -H "Authorization: Bearer <token>"
```

## Response

### Success (200)

```json
{
  "success": true,
  "filechecks": [
    {
      "name": "prod-storage",
      "storageAccount": "mystorageaccount",
      "authType": "sas"
    },
    {
      "name": "dev-storage",
      "storageAccount": "devstorageaccount",
      "authType": "azure-auth"
    }
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
- Returns an array of all file checks with their name, storage account, and auth type.
