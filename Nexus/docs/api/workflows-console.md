# Get Workflow Console Output

Returns the current console output for a running or recently completed workflow execution.

## Request

`GET /api/workflows/:name/console`

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
curl -X GET "http://nexus:8080/api/workflows/nightly-deploy/console" -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIs..."
```

## Response

### Success (200) — While Running

```json
{
  "running": true,
  "output": "[Step 1/3] Pull latest\nCloning into 'repo'...\ndone.\n[Step 2/3] Run migrations\nApplying migration 001..."
}
```

### Success (200) — After Completion

```json
{
  "running": false,
  "output": "[Step 1/3] Pull latest\ndone.\n[Step 2/3] Run migrations\ndone.\n[Step 3/3] Restart service\ndone.",
  "status": "success",
  "message": "Workflow 'nightly-deploy' completed"
}
```

### Error (4xx)

| Status | Body                                                  |
|--------|-------------------------------------------------------|
| 401    | `{ "success": false, "message": "Unauthorized" }`    |

## Notes

- Reads from a temporary console log file that is written to during execution.
- The `status` and `message` fields are only present once execution completes.
- Poll this endpoint periodically to stream output to the UI.
