# List Workflows

Returns all saved workflow definitions with summary info.

## Request

`GET /api/workflows`

### Headers

| Header          | Value              | Required |
|-----------------|--------------------|----------|
| Authorization   | Bearer {token}     | Yes      |

### Parameters

None.

### Example Request (curl)

```bash
curl -X GET "http://nexus:8080/api/workflows" -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIs..."
```

## Response

### Success (200)

```json
{
  "success": true,
  "workflows": [
    {
      "name": "nightly-deploy",
      "stepCount": 5
    },
    {
      "name": "db-backup",
      "stepCount": 3
    }
  ]
}
```

### Error (4xx)

| Status | Body                                                  |
|--------|-------------------------------------------------------|
| 401    | `{ "success": false, "message": "Unauthorized" }`    |

## Notes

- Returns an empty array if no workflows have been created.
