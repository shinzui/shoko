"""Private bounded-child HTTP GET; never renders addresses, errors or bodies."""
import json
import os
import ssl
import sys
import urllib.request


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def main():
    request = json.load(sys.stdin)
    endpoint, probe = request["endpoint"], request["probe"]
    headers = {}
    references = endpoint["credentialEnv"]
    if len(references) > 1:
        return 2
    if references:
        token = os.environ.get(references[0])
        if not token:
            return 2
        headers["Authorization"] = "Bearer " + token
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect(), urllib.request.HTTPSHandler(context=ssl.create_default_context()))
    url = endpoint["address"].rstrip("/") + probe["path"]
    with opener.open(urllib.request.Request(url, headers=headers, method="GET"), timeout=10) as response:
        return 0 if response.status == probe["expectedStatus"] and len(response.read(65537)) <= 65536 else 2


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception:
        raise SystemExit(2) from None
