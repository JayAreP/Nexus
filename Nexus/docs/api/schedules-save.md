# Save Schedule

Creates or updates a workflow schedule. Can also be used to toggle a schedule's enabled state.

## Request

`POST /api/schedules`

### Headers

| Header          | Value              | Required |
|-----------------|--------------------|----------|
| Authorization   | Bearer {token}     | Yes      |
| Content-Type    | application/json   | Yes      |

### Parameters / Body

| Field         | Type    | Required | Description                                              |
|---------------|---------|----------|----------------------------------------------------------|
| name          | string  | Yes      | Unique schedule identifier                               |
| workflow      | string  | Yes      | Name of the workflow to run                              |
| interval      | string  | No       | One of: `hourly`, `daily`, `weekly`, `monthly`           |
| nextRun       | string  | No       | ISO 8601 datetime for next execution                     |
| enabled       | boolean | No       | Whether the schedule is active                           |
| toggleEnabled | boolean | No       | If true, only toggles the enabled state (no other updates) |

### Example Request (curl)

```bash
curl -X POST http://nexus:8080/api/schedules -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..." -H "Content-Type: application/json" -d '{"name":"nightly-backup","workflow":"backup-databases","interval":"daily","nextRun":"2026-03-22T02:00:00.000Z","enabled":true}'
```

Toggle-only example:

```bash
curl -X POST http://nexus:8080/api/schedules -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..." -H "Content-Type: application/json" -d '{"name":"nightly-backup","workflow":"backup-databases","toggleEnabled":true}'
```

## Response

### Success (200)

```json
{
  "success": true,
  "message": "Schedule saved"
}
```

### Error (4xx)

```json
{
  "success": false,
  "error": "Missing required fields: name, workflow"
}
```

## Notes

- If a schedule with the same `name` already exists, it will be overwritten.
- When `toggleEnabled` is true, only the enabled state is flipped; other fields are ignored.
