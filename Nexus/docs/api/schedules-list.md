# List Schedules

Returns all configured workflow schedules.

## Request

`GET /api/schedules`

### Headers

| Header          | Value            | Required |
|-----------------|------------------|----------|
| Authorization   | Bearer {token}   | Yes      |

### Parameters / Body

None.

### Example Request (curl)

```bash
curl -X GET http://nexus:8080/api/schedules -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

## Response

### Success (200)

```json
{
  "success": true,
  "schedules": [
    {
      "name": "nightly-backup",
      "workflow": "backup-databases",
      "interval": "daily",
      "nextRun": "2026-03-22T02:00:00.000Z",
      "enabled": true
    },
    {
      "name": "weekly-report",
      "workflow": "generate-report",
      "interval": "weekly",
      "nextRun": "2026-03-28T08:00:00.000Z",
      "enabled": false
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

- Returns an empty array if no schedules are configured.
