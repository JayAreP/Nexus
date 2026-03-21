# Reset Sandbox

Deletes all files in the sandbox workspace, restoring it to a clean state.

## Request

`POST /api/sandbox/reset`

### Headers

| Header          | Value              | Required |
|-----------------|--------------------|----------|
| `Authorization` | `Bearer <token>`   | Yes      |

### Body

No body required.

### Example Request (curl)

```bash
curl -X POST http://nexus:8080/api/sandbox/reset \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

## Response

### Success (200)

```json
{
  "success": true,
  "message": "Sandbox workspace has been reset"
}
```

### Error (4xx)

| Status | Body                                        |
|--------|---------------------------------------------|
| 401    | `{ "error": "Authentication required" }`    |

## Notes

- Deletes all files in `/home/sandbox/workspace`.
- The workspace directory itself is preserved; only its contents are removed.
