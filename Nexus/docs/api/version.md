# Get Version

Returns the current server version and server time.

## Request

`GET /api/version`

### Headers

No headers required. This endpoint does not require authentication.

### Parameters

None.

### Example Request (curl)

```bash
curl http://nexus:8080/api/version
```

## Response

### Success (200)

```json
{
  "version": "1.2.0",
  "serverTime": "2026-03-21 14:30:00"
}
```

| Field        | Type   | Description                                      |
|--------------|--------|--------------------------------------------------|
| `version`    | string | Server version string                            |
| `serverTime` | string | Current server time in `YYYY-MM-DD HH:mm:ss` format |

### Error (4xx)

This endpoint does not produce client errors under normal conditions.

## Notes

- Reads the version from `./version.txt` on disk.
- If `version.txt` is missing or unreadable, `version` returns `"dev"`.
- No authentication is required, making this suitable for health checks.
