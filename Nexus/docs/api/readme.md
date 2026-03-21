# Nexus API Documentation

The Nexus API provides programmatic access to the automation sequencer. All endpoints return JSON and are served behind nginx on port **8080**.

---

## Authentication

All API calls (except where noted) require a **Bearer token** in the `Authorization` header:

```
Authorization: Bearer <token>
```

### Obtaining a Session Token

Send your credentials to the login endpoint:

```bash
curl -X POST http://nexus:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "nexus", "password": "nexus"}'
```

Response:

```json
{
  "success": true,
  "token": "abc123...",
  "username": "nexus",
  "role": "admin",
  "expiresAt": "2026-03-22T00:00:00.0000000+00:00"
}
```

Session tokens expire after **8 hours**.

### Using an API Token (Permanent)

Admins can generate permanent API tokens from the **Users** panel in the web UI, or via the [Create API Token](auth-create-token.md) endpoint. API tokens do not expire and are ideal for CI/CD integrations.

Use them the same way:

```bash
curl http://nexus:8080/api/workflows \
  -H "Authorization: Bearer <api-token>"
```

### Public Endpoints (No Auth Required)

| Endpoint | Description |
|----------|-------------|
| `GET /api/version` | Server version and time |
| `POST /api/auth/login` | Obtain a session token |

---

## API Reference

### Authentication

| Method | Endpoint | Description | Doc |
|--------|----------|-------------|-----|
| POST | `/api/auth/login` | Obtain a session token | [auth-login.md](auth-login.md) |
| POST | `/api/auth/logout` | Invalidate current session | [auth-logout.md](auth-logout.md) |
| GET | `/api/auth/session` | Verify token / get user info | [auth-session.md](auth-session.md) |
| GET | `/api/auth/users` | List all users | [auth-list-users.md](auth-list-users.md) |
| POST | `/api/auth/users` | Create a user | [auth-create-user.md](auth-create-user.md) |
| PUT | `/api/auth/users/:username` | Update a user | [auth-update-user.md](auth-update-user.md) |
| DELETE | `/api/auth/users/:username` | Delete a user | [auth-delete-user.md](auth-delete-user.md) |
| GET | `/api/auth/tokens` | List API tokens | [auth-list-tokens.md](auth-list-tokens.md) |
| POST | `/api/auth/tokens` | Create an API token | [auth-create-token.md](auth-create-token.md) |
| DELETE | `/api/auth/tokens/:id` | Revoke an API token | [auth-delete-token.md](auth-delete-token.md) |

### System

| Method | Endpoint | Description | Doc |
|--------|----------|-------------|-----|
| GET | `/api/version` | Server version and time | [version.md](version.md) |
| GET | `/api/dashboard` | Dashboard statistics | [dashboard.md](dashboard.md) |

### Configuration

| Method | Endpoint | Description | Doc |
|--------|----------|-------------|-----|
| GET | `/api/config` | Get storage configuration | [config-get.md](config-get.md) |
| POST | `/api/config` | Save storage configuration | [config-save.md](config-save.md) |
| POST | `/api/config/prepare` | Create storage containers | [config-prepare.md](config-prepare.md) |

### Scripts

| Method | Endpoint | Description | Doc |
|--------|----------|-------------|-----|
| GET | `/api/scripts/:type` | List scripts by type | [scripts-list.md](scripts-list.md) |
| POST | `/api/scripts/:type` | Upload a script | [scripts-upload.md](scripts-upload.md) |
| GET | `/api/scripts/:type/:name/content` | Get script content | [scripts-get-content.md](scripts-get-content.md) |
| PUT | `/api/scripts/:type/:name` | Update script content | [scripts-update.md](scripts-update.md) |
| GET | `/api/scripts/:type/:name/parameters` | Extract script parameters | [scripts-parameters.md](scripts-parameters.md) |
| DELETE | `/api/scripts/:type/:name` | Delete a script | [scripts-delete.md](scripts-delete.md) |
| POST | `/api/scripts/:type/:name/copy` | Duplicate a script | [scripts-copy.md](scripts-copy.md) |

### Workflows

| Method | Endpoint | Description | Doc |
|--------|----------|-------------|-----|
| GET | `/api/workflows` | List all workflows | [workflows-list.md](workflows-list.md) |
| GET | `/api/workflows/:name` | Get workflow definition | [workflows-get.md](workflows-get.md) |
| POST | `/api/workflows` | Create or update a workflow | [workflows-save.md](workflows-save.md) |
| DELETE | `/api/workflows/:name` | Delete a workflow | [workflows-delete.md](workflows-delete.md) |
| POST | `/api/workflows/:name/copy` | Duplicate a workflow | [workflows-copy.md](workflows-copy.md) |
| GET | `/api/workflows/:name/export` | Export workflow as JSON | [workflows-export.md](workflows-export.md) |
| POST | `/api/workflows/import` | Import a workflow from JSON | [workflows-import.md](workflows-import.md) |

### Workflow Execution

| Method | Endpoint | Description | Doc |
|--------|----------|-------------|-----|
| POST | `/api/workflows/:name/run` | Run a workflow | [workflows-run.md](workflows-run.md) |
| POST | `/api/workflows/:name/run-step` | Run a single step | [workflows-run-step.md](workflows-run-step.md) |
| GET | `/api/workflows/:name/console` | Poll live console output | [workflows-console.md](workflows-console.md) |

### Webhooks

| Method | Endpoint | Description | Doc |
|--------|----------|-------------|-----|
| GET | `/api/webhooks` | List webhook configs | [webhooks-list.md](webhooks-list.md) |
| POST | `/api/webhooks` | Create a webhook config | [webhooks-create.md](webhooks-create.md) |
| GET | `/api/webhooks/:name` | Get webhook config | [webhooks-get.md](webhooks-get.md) |
| DELETE | `/api/webhooks/:name` | Delete a webhook config | [webhooks-delete.md](webhooks-delete.md) |
| POST | `/api/webhooks/:name/copy` | Duplicate a webhook config | [webhooks-copy.md](webhooks-copy.md) |

### File Checks

| Method | Endpoint | Description | Doc |
|--------|----------|-------------|-----|
| GET | `/api/filechecks` | List file check configs | [filechecks-list.md](filechecks-list.md) |
| POST | `/api/filechecks` | Create a file check config | [filechecks-create.md](filechecks-create.md) |
| GET | `/api/filechecks/:name` | Get file check config | [filechecks-get.md](filechecks-get.md) |
| DELETE | `/api/filechecks/:name` | Delete a file check config | [filechecks-delete.md](filechecks-delete.md) |
| POST | `/api/filechecks/:name/copy` | Duplicate a file check config | [filechecks-copy.md](filechecks-copy.md) |
| GET | `/api/filechecks/:name/containers` | List storage containers | [filechecks-containers.md](filechecks-containers.md) |
| GET | `/api/filechecks/:name/browse` | Browse container contents | [filechecks-browse.md](filechecks-browse.md) |

### Credentials

| Method | Endpoint | Description | Doc |
|--------|----------|-------------|-----|
| GET | `/api/credentials/types` | List credential type schemas | [credentials-types.md](credentials-types.md) |
| GET | `/api/credentials` | List credentials (metadata) | [credentials-list.md](credentials-list.md) |
| GET | `/api/credentials/:name` | Get credential (masked) | [credentials-get.md](credentials-get.md) |
| POST | `/api/credentials` | Create or update a credential | [credentials-save.md](credentials-save.md) |
| DELETE | `/api/credentials/:name` | Delete a credential | [credentials-delete.md](credentials-delete.md) |
| POST | `/api/credentials/:name/copy` | Duplicate a credential | [credentials-copy.md](credentials-copy.md) |
| GET | `/api/credentials/:name/resolve` | Resolve credential (decrypted) | [credentials-resolve.md](credentials-resolve.md) |

### Schedules

| Method | Endpoint | Description | Doc |
|--------|----------|-------------|-----|
| GET | `/api/schedules` | List schedules | [schedules-list.md](schedules-list.md) |
| POST | `/api/schedules` | Create or update a schedule | [schedules-save.md](schedules-save.md) |
| DELETE | `/api/schedules/:name` | Delete a schedule | [schedules-delete.md](schedules-delete.md) |

### Logs

| Method | Endpoint | Description | Doc |
|--------|----------|-------------|-----|
| GET | `/api/logs/:workflow` | List workflow run logs | [logs-list.md](logs-list.md) |
| GET | `/api/logs/:workflow/:logName` | Get a specific log | [logs-get.md](logs-get.md) |
| DELETE | `/api/logs/:workflow/clear` | Clear old logs | [logs-clear.md](logs-clear.md) |
| GET | `/api/engine-logs` | List engine log files | [engine-logs-list.md](engine-logs-list.md) |
| GET | `/api/engine-log` | Get engine log content | [engine-log-get.md](engine-log-get.md) |

### Packages / Modules

| Method | Endpoint | Description | Doc |
|--------|----------|-------------|-----|
| GET | `/api/modules/:type` | List installed modules | [modules-list.md](modules-list.md) |
| POST | `/api/modules/:type` | Install a module | [modules-install.md](modules-install.md) |
| DELETE | `/api/modules/:name` | Uninstall a module | [modules-delete.md](modules-delete.md) |
| POST | `/api/modules/github` | Install module from GitHub | [modules-github.md](modules-github.md) |

### Sandbox

| Method | Endpoint | Description | Doc |
|--------|----------|-------------|-----|
| GET | `/api/sandbox/status` | Check terminal status | [sandbox-status.md](sandbox-status.md) |
| POST | `/api/sandbox/reset` | Reset sandbox workspace | [sandbox-reset.md](sandbox-reset.md) |

---

## Error Responses

All error responses follow the same format:

```json
{
  "success": false,
  "message": "Description of what went wrong"
}
```

Common HTTP status codes:

| Code | Meaning |
|------|---------|
| 400 | Bad request (missing or invalid parameters) |
| 401 | Authentication required or token expired |
| 403 | Forbidden (admin-only endpoint) |
| 404 | Resource not found |
| 409 | Conflict (e.g., workflow already running) |
| 500 | Server error |
