# Get Dashboard

Returns an aggregated overview of workflow counts, recent activity, trends, and performance statistics.

## Request

`GET /api/dashboard`

### Headers

| Header          | Value              | Required |
|-----------------|--------------------|----------|
| `Authorization` | `Bearer <token>`   | Yes      |

### Parameters

| Param     | Type   | In    | Required | Description                          |
|-----------|--------|-------|----------|--------------------------------------|
| `refresh` | string | query | No       | Set to `"true"` to bypass the cache  |

### Example Request (curl)

```bash
curl http://nexus:8080/api/dashboard?refresh=true \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

## Response

### Success (200)

```json
{
  "success": true,
  "counts": {
    "workflows": 12,
    "scripts": 34,
    "schedules": 5,
    "webhooks": 3,
    "filechecks": 2,
    "credentials": 7
  },
  "running": ["daily-backup", "sync-users"],
  "last24h": {
    "total": 48,
    "success": 45,
    "failed": 3,
    "successRate": 93.75,
    "avgDuration": 12400,
    "longestRun": {
      "workflow": "full-export",
      "duration": 94200
    }
  },
  "trend": [
    { "date": "2026-03-20", "label": "Mar 20", "success": 40, "failed": 2 },
    { "date": "2026-03-21", "label": "Mar 21", "success": 45, "failed": 3 }
  ],
  "mostRun": [
    { "workflow": "daily-backup", "count": 24 },
    { "workflow": "sync-users", "count": 18 }
  ],
  "mostFailing": [
    { "workflow": "legacy-import", "failures": 5, "total": 12, "rate": 41.67 }
  ],
  "slowest": [
    { "workflow": "full-export", "avgDuration": 89000, "runs": 6 }
  ],
  "recentFailures": [
    { "workflow": "legacy-import", "when": "2h ago", "time": "2026-03-21 12:15:00" }
  ],
  "stepTypeStats": [
    { "type": "powershell", "total": 120, "failures": 4 },
    { "type": "terraform", "total": 30, "failures": 1 }
  ],
  "cached": false,
  "cacheAge": 0
}
```

| Field            | Type      | Description                                           |
|------------------|-----------|-------------------------------------------------------|
| `counts`         | object    | Total counts of each resource type                    |
| `running`        | string[]  | Names of currently executing workflows                |
| `last24h`        | object    | Aggregated statistics for the last 24 hours           |
| `trend`          | array     | Per-day success/failure counts for the trend chart    |
| `mostRun`        | array     | Workflows ordered by execution count                  |
| `mostFailing`    | array     | Workflows with the highest failure rates              |
| `slowest`        | array     | Workflows with the longest average durations          |
| `recentFailures` | array     | Most recent workflow failures                         |
| `stepTypeStats`  | array     | Execution and failure totals grouped by step type     |
| `cached`         | boolean   | Whether the response was served from cache            |
| `cacheAge`       | integer   | Age of the cached data in milliseconds                |

### Error (4xx)

| Status | Body                                        |
|--------|---------------------------------------------|
| 401    | `{ "error": "Authentication required" }`    |

## Notes

- Responses are cached with a 2-minute TTL. Pass `refresh=true` to force a fresh query.
- The `running` array is always fetched live, even when the rest of the response is cached.
- `cacheAge` is `0` when `cached` is `false`.
