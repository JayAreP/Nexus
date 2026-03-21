# List Workflow Logs

Returns a list of log files for a specific workflow.

## Request

`GET /api/logs/:workflow`

### Headers

| Header          | Value            | Required |
|-----------------|------------------|----------|
| Authorization   | Bearer {token}   | Yes      |

### Parameters / Body

| Parameter | Location | Type   | Required | Description              |
|-----------|----------|--------|----------|--------------------------|
| workflow  | URL      | string | Yes      | Workflow name            |

### Example Request (curl)

```bash
curl -X GET http://nexus:8080/api/logs/backup-databases -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

## Response

### Success (200)

```json
{
  "success": true,
  "logs": [
    {
      "name": "2026-03-21_14-30-00.json",
      "lastModified": "2026-03-21T14:30:45.000Z"
    },
    {
      "name": "2026-03-20_02-00-00.json",
      "lastModified": "2026-03-20T02:01:12.000Z"
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

- Reads from the `{workflow-container}/logs/` prefix in storage.
- Log files are named with the timestamp of the workflow run.
- Returns an empty array if no logs exist for the workflow.
