# Delete Workflow

Deletes a workflow definition by name.

## Request

`DELETE /api/workflows/:name`

### Headers

| Header          | Value              | Required |
|-----------------|--------------------|----------|
| Authorization   | Bearer {token}     | Yes      |

### Parameters

| Parameter | In   | Type   | Required | Description          |
|-----------|------|--------|----------|----------------------|
| name      | path | string | Yes      | Name of the workflow |

### Example Request (curl)

```bash
curl -X DELETE "http://nexus:8080/api/workflows/nightly-deploy" -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIs..."
```

## Response

### Success (200)

```json
{
  "success": true,
  "message": "Workflow 'nightly-deploy' deleted"
}
```

### Error (4xx)

| Status | Body                                                  |
|--------|-------------------------------------------------------|
| 401    | `{ "success": false, "message": "Unauthorized" }`    |

## Notes

- Deleting a workflow that does not exist may still return a success response.
