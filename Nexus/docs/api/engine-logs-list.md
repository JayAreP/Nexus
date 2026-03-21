# List Engine Logs

Returns a list of Nexus engine log files, sorted newest first.

## Request

`GET /api/engine-logs`

### Headers

| Header          | Value            | Required |
|-----------------|------------------|----------|
| Authorization   | Bearer {token}   | Yes      |

### Parameters / Body

None.

### Example Request (curl)

```bash
curl -X GET http://nexus:8080/api/engine-logs -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

## Response

### Success (200)

```json
{
  "success": true,
  "logs": [
    {
      "date": "2026-03-21",
      "size": 4096
    },
    {
      "date": "2026-03-20",
      "size": 12288
    }
  ]
}
```

### Error (4xx)

```json
{
  "success": false,
  "error": "Unauthorized"
}
```

## Notes

- Lists `nexus-engine-*.log` files from the engine log directory.
- Results are sorted newest first.
- The `size` field is in bytes.
