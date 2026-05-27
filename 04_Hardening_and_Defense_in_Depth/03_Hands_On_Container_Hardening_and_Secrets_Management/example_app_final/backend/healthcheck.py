import json
import os
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

URL = os.getenv("HEALTHCHECK_URL", "http://127.0.0.1:8000/api/health")
TIMEOUT_SECONDS = float(os.getenv("HEALTHCHECK_TIMEOUT", "3"))


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    sys.exit(1)


try:
    request = Request(URL, headers={"Accept": "application/json"})
    with urlopen(request, timeout=TIMEOUT_SECONDS) as response:  # noqa: S310 - local container health check
        status_code = response.getcode()
        payload = json.loads(response.read().decode("utf-8"))
except HTTPError as exc:
    fail(f"backend health endpoint returned HTTP {exc.code}")
except (OSError, URLError, json.JSONDecodeError) as exc:
    fail(f"backend health check failed: {exc}")

if status_code != 200:
    fail(f"backend health endpoint returned HTTP {status_code}")

if payload.get("status") != "ok":
    fail(f"backend is not healthy: {payload}")

sys.exit(0)
