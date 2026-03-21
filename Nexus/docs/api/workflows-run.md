# Run Workflow

Starts asynchronous execution of an entire workflow.

## Request

`POST /api/workflows/:name/run`

### Headers

| Header          | Value              | Required |
|-----------------|--------------------|----------|
| Authorization   | Bearer {token}     | Yes      |

### Parameters

| Parameter | In   | Type   | Required | Description          |
|-----------|------|--------|----------|----------------------|
| name      | path | string | Yes      | Name of the workflow |

### Body

None required.

### Example Request (curl)

```bash
curl -X POST "http://nexus:8080/api/workflows/nightly-deploy/run" -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIs..."
```

## Response

### Success (200)

```json
{
  "success": true,
  "message": "Workflow 'nightly-deploy' started"
}
```

### Error (4xx)

| Status | Body                                                                  |
|--------|-----------------------------------------------------------------------|
| 401    | `{ "success": false, "message": "Unauthorized" }`                    |
| 409    | `{ "success": false, "message": "Workflow is already running" }`     |

## Notes

- Execution is asynchronous via a Pode timer. The endpoint returns immediately after scheduling.
- Poll `GET /api/workflows/:name/console` for live output and completion status.
- Only one instance of a workflow can run at a time; a second request returns `409`.
