# Get Sandbox Status

Returns whether the sandbox terminal (ttyd) is currently running.

## Request

`GET /api/sandbox/status`

### Headers

| Header          | Value              | Required |
|-----------------|--------------------|----------|
| `Authorization` | `Bearer <token>`   | Yes      |

### Parameters

None.

### Example Request (curl)

```bash
curl http://nexus:8080/api/sandbox/status \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

## Response

### Success (200)

```json
{
  "success": true,
  "running": true,
  "path": "/terminal/"
}
```

| Field     | Type    | Description                                  |
|-----------|---------|----------------------------------------------|
| `running` | boolean | `true` if the ttyd process is active         |
| `path`    | string  | URL path where the terminal UI is accessible |

### Error (4xx)

| Status | Body                                        |
|--------|---------------------------------------------|
| 401    | `{ "error": "Authentication required" }`    |

## Notes

- Checks for a running `ttyd` process to determine status.
- The terminal UI is served at the path returned in `path` (typically `/terminal/`).
