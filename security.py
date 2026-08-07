"""HTTP fetch helpers with SSRF protection.

Used for fetching user-supplied URLs (recipe import). Blocks non-HTTP
schemes, private/loopback/link-local address ranges, validates every
redirect hop, and caps response size.
"""
import ipaddress
import socket
from urllib.parse import urlparse, urljoin

import requests

MAX_RESPONSE_BYTES = 5 * 1024 * 1024  # 5 MB
DEFAULT_TIMEOUT = 15
MAX_REDIRECTS = 5


class FetchError(ValueError):
    """Raised when a URL is unsafe or a fetch fails."""


def _is_public_ip(ip_str: str) -> bool:
    try:
        ip = ipaddress.ip_address(ip_str)
    except ValueError:
        return False
    return not (
        ip.is_private or ip.is_loopback or ip.is_link_local
        or ip.is_multicast or ip.is_reserved or ip.is_unspecified
    )


def validate_public_url(url: str) -> None:
    """Raise FetchError unless url is http(s) and resolves only to public IPs."""
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https"):
        raise FetchError("Only http and https URLs are allowed.")
    host = parsed.hostname
    if not host:
        raise FetchError("Invalid URL.")
    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    try:
        infos = socket.getaddrinfo(host, port, proto=socket.IPPROTO_TCP)
    except socket.gaierror:
        raise FetchError("Could not resolve host.")
    if not infos:
        raise FetchError("Could not resolve host.")
    for info in infos:
        if not _is_public_ip(info[4][0]):
            raise FetchError("URL resolves to a private or internal address.")


def safe_get(url: str, *, headers: dict | None = None,
             timeout: int = DEFAULT_TIMEOUT,
             max_bytes: int = MAX_RESPONSE_BYTES) -> requests.Response:
    """GET a public URL with SSRF checks on every redirect hop and a size cap.

    Returns a Response whose .content/.text are fully loaded.
    Raises FetchError on any policy violation or non-200 final status.
    """
    current = url
    for _ in range(MAX_REDIRECTS + 1):
        validate_public_url(current)
        resp = requests.get(current, headers=headers, timeout=timeout,
                            stream=True, allow_redirects=False)
        try:
            if resp.is_redirect or resp.is_permanent_redirect:
                location = resp.headers.get("Location")
                if not location:
                    raise FetchError("Redirect without a Location header.")
                current = urljoin(current, location)
                continue
            if resp.status_code != 200:
                raise FetchError(f"Fetch failed with HTTP {resp.status_code}.")
            content = b""
            for chunk in resp.iter_content(64 * 1024):
                content += chunk
                if len(content) > max_bytes:
                    raise FetchError("Response too large.")
            resp._content = content  # make .content/.text available
            return resp
        finally:
            resp.close()
    raise FetchError("Too many redirects.")
