# Get Workflow Log

Retrieves a specific log file for a workflow. Supports both JSON and plain-text log formats.

## Request

`GET /api/logs/:workflow/:logName`

### Headers

| Header          | Value            | Required |
|-----------------|------------------|----------|
| Authorization   | Bearer {token}   | Yes      |

### Parameters / Body

| Parameter | Location | Type   | Required | Description                          |
|-----------|----------|--------|----------|--------------------------------------|
| workflow  | URL      | string | Yes      | Workflow name                        |
| logName   | URL      | string | Yes      | Log filename (e.g. `2026-03-21_14-30-00.json`) |

### Example Request (curl)

```bash
curl -X GET http://nexus:8080/api/logs/backup-databases/2026-03-21_14-30-00.json -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

## Response

### Success (200) -- JSON log

```json
{
  "success": true,
  "log": {
    "startedAt": "2026-03-21T14:30:00.000Z",
    "completedAt": "2026-03-21T14:30:45.000Z",
    "status": "success",
    "steps": [
      { "name": "dump-postgres", "duration": 32, "status": "success" }
    ]
  }
}
```

### Success (200) -- .log file (plain text)

```json
{
  "success": true,
  "log": "2026-03-21 14:30:00 [INFO] Starting backup...\n2026-03-21 14:30:45 [INFO] Backup complete."
}
```

### Error (404)

```json
{
  "success": false,
  "error": "Log not found"
}
```

## Notes

- JSON log files (`.json`) are parsed and returned as objects.
- Plain-text log files (`.log`) are returned as raw string content.
