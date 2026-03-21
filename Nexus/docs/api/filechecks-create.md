# Create File Check

Creates a new file check configuration.

## Request

`POST /api/filechecks`

### Headers

| Header          | Value              | Required |
|-----------------|--------------------|----------|
| `Authorization` | `Bearer <token>`   | Yes      |
| `Content-Type`  | `application/json` | Yes      |

### Body

| Field            | Type   | Required                  | Description                          |
|------------------|--------|---------------------------|--------------------------------------|
| `name`           | string | Yes                       | Unique name for the file check       |
| `storageAccount` | string | Yes                       | Azure storage account name           |
| `authType`       | string | Yes                       | `"sas"` or `"azure-auth"`           |
| `sasToken`       | string | Yes (if `authType`=`sas`) | SAS token for storage account access |

### Example Request (curl)

With SAS token auth:

```bash
curl -s -X POST http://nexus:8080/api/filechecks -H "Authorization: Bearer <token>" -H "Content-Type: application/json" -d '{"name": "prod-storage", "storageAccount": "mystorageaccount", "authType": "sas", "sasToken": "sv=2022-11-02&ss=b&srt=sco&sp=rl&se=2026-12-31T00:00:00Z&sig=xxxxx"}'
```

With Azure auth:

```bash
curl -s -X POST http://nexus:8080/api/filechecks -H "Authorization: Bearer <token>" -H "Content-Type: application/json" -d '{"name": "dev-storage", "storageAccount": "devstorageaccount", "authType": "azure-auth"}'
```

## Response

### Success (200)

```json
{
  "success": true,
  "message": "File check created successfully"
}
```

### Error (400)

```json
{
  "success": false,
  "message": "Name, storage account, and auth type are required"
}
```

## Notes

- Authentication is required.
- The `sasToken` field is required when `authType` is `"sas"`.
- When `authType` is `"azure-auth"`, the application uses its managed identity or configured Azure credentials.
