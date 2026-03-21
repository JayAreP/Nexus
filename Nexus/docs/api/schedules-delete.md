# Delete Schedule

Removes a workflow schedule by name.

## Request

`DELETE /api/schedules/:name`

### Headers

| Header          | Value            | Required |
|-----------------|------------------|----------|
| Authorization   | Bearer {token}   | Yes      |

### Parameters / Body

| Parameter | Location | Type   | Required | Description              |
|-----------|----------|--------|----------|--------------------------|
| name      | URL      | string | Yes      | Name of the schedule     |

### Example Request (curl)

```bash
curl -X DELETE http://nexus:8080/api/schedules/nightly-backup -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

## Response

### Success (200)

```json
{
  "success": true,
  "message": "Schedule deleted"
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

- No error is returned if the schedule does not exist; the operation is idempotent.
