# Clear Workflow Logs

Deletes logs older than a specified number of days for a given workflow.

## Request

`DELETE /api/logs/:workflow/clear`

### Headers

| Header          | Value            | Required |
|-----------------|------------------|----------|
| Authorization   | Bearer {token}   | Yes      |

### Parameters / Body

| Parameter | Location | Type   | Required | Default | Description                        |
|-----------|----------|--------|----------|---------|------------------------------------|
| workflow  | URL      | string | Yes      |         | Workflow name                      |
| days      | Query    | number | No       | 30      | Delete logs older than this many days |

### Example Request (curl)

```bash
curl -X DELETE "http://nexus:8080/api/logs/backup-databases/clear?days=14" -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

## Response

### Success (200)

```json
{
  "success": true,
  "message": "Cleared 12 logs older than 14 days"
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

- If `days` is omitted, defaults to 30.
- Returns a count of how many log files were removed.
