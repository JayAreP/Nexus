# Delete Webhook

Deletes a webhook by name.

## Request

`DELETE /api/webhooks/:name`

### Headers

| Header          | Value            | Required |
|-----------------|------------------|----------|
| `Authorization` | `Bearer <token>` | Yes      |

### Parameters

| Parameter | Location | Required | Description          |
|-----------|----------|----------|----------------------|
| `name`    | Path     | Yes      | Name of the webhook  |

### Example Request (curl)

```bash
curl -s -X DELETE http://nexus:8080/api/webhooks/deploy-notification -H "Authorization: Bearer <token>"
```

## Response

### Success (200)

```json
{
  "success": true,
  "message": "Webhook deleted successfully"
}
```

### Error (401)

```json
{
  "success": false,
  "message": "Unauthorized"
}
```

## Notes

- Authentication is required.
