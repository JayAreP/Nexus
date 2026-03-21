# Copy Webhook

Creates a duplicate of an existing webhook under a new name.

## Request

`POST /api/webhooks/:name/copy`

### Headers

| Header          | Value              | Required |
|-----------------|--------------------|----------|
| `Authorization` | `Bearer <token>`   | Yes      |
| `Content-Type`  | `application/json` | Yes      |

### Parameters

| Parameter | Location | Required | Description                    |
|-----------|----------|----------|--------------------------------|
| `name`    | Path     | Yes      | Name of the webhook to copy    |

### Body

| Field     | Type   | Required | Description                  |
|-----------|--------|----------|------------------------------|
| `newName` | string | Yes      | Name for the copied webhook  |

### Example Request (curl)

```bash
curl -s -X POST http://nexus:8080/api/webhooks/deploy-notification/copy -H "Authorization: Bearer <token>" -H "Content-Type: application/json" -d '{"newName": "deploy-notification-v2"}'
```

## Response

### Success (200)

```json
{
  "success": true,
  "message": "Webhook copied successfully"
}
```

### Error (400)

```json
{
  "success": false,
  "message": "New name is required"
}
```

### Error (404)

```json
{
  "success": false,
  "message": "Webhook not found"
}
```

## Notes

- Authentication is required.
- The new webhook is an independent copy; changes to either do not affect the other.
