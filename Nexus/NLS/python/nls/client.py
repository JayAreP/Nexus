"""NLS client — credential retrieval from the Nexus API."""

import os
import urllib.request
import urllib.parse
import urllib.error
import json

_server_url = os.environ.get("NEXUS_SERVER_URL", "http://localhost:8080")


def set_server(url: str) -> None:
    """Set the Nexus server URL for this session.

    Args:
        url: Base URL of the Nexus server (e.g. 'http://localhost:8080').
    """
    global _server_url
    _server_url = url.rstrip("/")


def get_credential(name: str) -> dict:
    """Retrieve decrypted credentials from the Nexus credential store.

    Calls the Nexus ``/api/credentials/<name>/resolve`` endpoint and
    returns a dictionary of the credential's key/value pairs with all
    secrets decrypted.

    Args:
        name: The name of the stored credential.

    Returns:
        A dict of credential values, e.g. ``{"username": "admin", "password": "secret"}``.

    Raises:
        RuntimeError: If the credential is not found or the request fails.

    Examples::

        import nls

        # Simple username/password
        creds = nls.get_credential("prod-db-login")
        conn_str = f"Server=sql01;User={creds['username']};Password={creds['password']}"

        # AWS credentials
        aws = nls.get_credential("aws-production")
        import boto3
        session = boto3.Session(
            aws_access_key_id=aws["accessKeyId"],
            aws_secret_access_key=aws["secretAccessKey"],
            region_name=aws.get("region", "us-east-1"),
        )

        # Azure Service Principal
        sp = nls.get_credential("azure-sp-prod")
    """
    encoded_name = urllib.parse.quote(name, safe="")
    url = f"{_server_url}/api/credentials/{encoded_name}/resolve"

    req = urllib.request.Request(url, method="GET")
    req.add_header("Accept", "application/json")

    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        try:
            err_data = json.loads(body)
            msg = err_data.get("message", body)
        except json.JSONDecodeError:
            msg = body
        raise RuntimeError(
            f"Failed to retrieve credential '{name}': {msg}"
        ) from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(
            f"Cannot connect to Nexus at {_server_url}: {exc.reason}"
        ) from exc

    if data.get("success") and data.get("credential", {}).get("values"):
        return dict(data["credential"]["values"])

    msg = data.get("message", f"Failed to resolve credential '{name}'")
    raise RuntimeError(msg)
