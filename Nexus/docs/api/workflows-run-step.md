# Run Workflow Step

Runs a single step from a workflow for testing purposes.

## Request

`POST /api/workflows/:name/run-step`

### Headers

| Header          | Value              | Required |
|-----------------|--------------------|----------|
| Authorization   | Bearer {token}     | Yes      |
| Content-Type    | application/json   | Yes      |

### Parameters

| Parameter | In   | Type   | Required | Description          |
|-----------|------|--------|----------|----------------------|
| name      | path | string | Yes      | Name of the workflow |

### Body

```json
{
  "stepIndex": 0
}
```

| Field     | Type    | Required | Description                      |
|-----------|---------|----------|----------------------------------|
| stepIndex | integer | Yes      | Zero-based index of the step     |

### Example Request (curl)

```bash
curl -X POST "http://nexus:8080/api/workflows/nightly-deploy/run-step" -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIs..." -H "Content-Type: application/json" -d '{"stepIndex":0}'
```

## Response

### Success (200)

```json
{
  "success": true,
  "message": "Step 0 of workflow 'nightly-deploy' started"
}
```

### Error (4xx)

| Status | Body                                                                  |
|--------|-----------------------------------------------------------------------|
| 401    | `{ "success": false, "message": "Unauthorized" }`                    |
| 409    | `{ "success": false, "message": "Workflow is already running" }`     |

## Notes

- Execution is asynchronous. Poll `GET /api/workflows/:name/console` for output.
- Useful for testing individual steps without running the entire workflow.
- Only one instance of a workflow can run at a time; a second request returns `409`.
