# Get Engine Log

Retrieves the contents of a specific engine log file by date.

## Request

`GET /api/engine-log`

### Headers

| Header          | Value            | Required |
|-----------------|------------------|----------|
| Authorization   | Bearer {token}   | Yes      |

### Parameters / Body

| Parameter | Location | Type   | Required | Default | Description                      |
|-----------|----------|--------|----------|---------|----------------------------------|
| date      | Query    | string | No       | today   | Date in `YYYY-MM-DD` format     |

### Example Request (curl)

```bash
curl -X GET "http://nexus:8080/api/engine-log?date=2026-03-21" -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

## Response

### Success (200)

```json
{
  "success": true,
  "log": "2026-03-21 14:00:00 [INFO] Server started...\n2026-03-21 14:00:01 [INFO] Loaded 5 schedules\n2026-03-21 14:05:00 [INFO] Running workflow: backup-databases"
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

- If `date` is omitted, defaults to today's date.
- Returns `"(no log for {date})"` as the `log` value if no log file exists for the requested date.
