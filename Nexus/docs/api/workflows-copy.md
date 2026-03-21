# Copy Workflow

Creates a duplicate of an existing workflow under a new name.

## Request

`POST /api/workflows/:name/copy`

### Headers

| Header          | Value              | Required |
|-----------------|--------------------|----------|
| Authorization   | Bearer {token}     | Yes      |
| Content-Type    | application/json   | Yes      |

### Parameters

| Parameter | In   | Type   | Required | Description                        |
|-----------|------|--------|----------|------------------------------------|
| name      | path | string | Yes      | Name of the workflow to copy       |

### Body

```json
{
  "newName": "nightly-deploy-v2"
}
```

| Field   | Type   | Required | Description                    |
|---------|--------|----------|--------------------------------|
| newName | string | Yes      | Name for the copied workflow   |

### Example Request (curl)

```bash
curl -X POST "http://nexus:8080/api/workflows/nightly-deploy/copy" -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIs..." -H "Content-Type: application/json" -d '{"newName":"nightly-deploy-v2"}'
```

## Response

### Success (200)

```json
{
  "success": true,
  "message": "Workflow copied to 'nightly-deploy-v2'"
}
```

### Error (4xx)

| Status | Body                                                  |
|--------|-------------------------------------------------------|
| 401    | `{ "success": false, "message": "Unauthorized" }`    |

## Notes

- The new workflow is an independent copy; changes to one do not affect the other.
