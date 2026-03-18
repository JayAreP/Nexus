"""NLS client — credential retrieval and script management from the Nexus API."""

import os
import urllib.request
import urllib.parse
import urllib.error
import json
import pathlib

_server_url = os.environ.get("NEXUS_SERVER_URL", "http://localhost:8080")

_VALID_SCRIPT_TYPES = ("powershell", "terraform", "python", "shell")


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


def _api_get(path: str) -> dict:
    """Internal helper — GET a JSON endpoint and return parsed dict."""
    url = f"{_server_url}{path}"
    req = urllib.request.Request(url, method="GET")
    req.add_header("Accept", "application/json")
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        try:
            msg = json.loads(body).get("message", body)
        except json.JSONDecodeError:
            msg = body
        raise RuntimeError(msg) from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(
            f"Cannot connect to Nexus at {_server_url}: {exc.reason}"
        ) from exc


def get_scripts(script_type: str) -> list[dict]:
    """List available scripts of a given type.

    Args:
        script_type: One of 'powershell', 'terraform', 'python', or 'shell'.

    Returns:
        A list of dicts with keys ``name``, ``size``, ``lastModified``.

    Raises:
        ValueError: If script_type is invalid.
        RuntimeError: If the request fails.

    Examples::

        import nls
        for s in nls.get_scripts("powershell"):
            print(s["name"])
    """
    st = script_type.lower()
    if st not in _VALID_SCRIPT_TYPES:
        raise ValueError(
            f"Invalid script_type '{script_type}'. "
            f"Must be one of: {', '.join(_VALID_SCRIPT_TYPES)}"
        )
    data = _api_get(f"/api/scripts/{st}")
    if data.get("success") and data.get("scripts"):
        return list(data["scripts"])
    return []


def copy_script(
    script_name: str,
    script_type: str,
    destination: str = "/home/sandbox/workspace",
) -> str:
    """Copy a script from the Nexus script store to a local directory.

    Args:
        script_name: The filename of the script (e.g. 'deploy.ps1').
        script_type: One of 'powershell', 'terraform', 'python', or 'shell'.
        destination: Local directory to write the file to.
            Defaults to '/home/sandbox/workspace'.

    Returns:
        The full path of the copied file.

    Raises:
        ValueError: If script_type is invalid.
        RuntimeError: If the script is not found or the request fails.

    Examples::

        import nls
        path = nls.copy_script("deploy.ps1", "powershell")
        print(f"Script saved to {path}")
    """
    st = script_type.lower()
    if st not in _VALID_SCRIPT_TYPES:
        raise ValueError(
            f"Invalid script_type '{script_type}'. "
            f"Must be one of: {', '.join(_VALID_SCRIPT_TYPES)}"
        )
    encoded = urllib.parse.quote(script_name, safe="")
    data = _api_get(f"/api/scripts/{st}/{encoded}/content")

    if not data.get("success") or data.get("content") is None:
        msg = data.get("message", f"Script '{script_name}' not found")
        raise RuntimeError(msg)

    dest = pathlib.Path(destination)
    dest.mkdir(parents=True, exist_ok=True)
    out_path = dest / script_name
    out_path.write_text(data["content"], encoding="utf-8")
    return str(out_path)
