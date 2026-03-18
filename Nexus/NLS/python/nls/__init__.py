"""NLS (Nexus Ladder Scheduler) - Python client for Nexus credential store and script management."""

from nls.client import get_credential, set_server, get_scripts, copy_script

__all__ = ["get_credential", "set_server", "get_scripts", "copy_script"]
__version__ = "1.0.0"
