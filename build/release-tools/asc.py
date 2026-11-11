"""Minimal App Store Connect API client. Credentials are read at run time, never printed."""
import json, os, sys, time, urllib.error, urllib.request, ssl
import certifi, jwt

_SSL = ssl.create_default_context(cafile=certifi.where())
HOME = os.path.expanduser("~")
APP = "6829637526"

def _env():
    values = {}
    with open(os.environ.get("ASC_ENV_FILE", f"{HOME}/.private_keys/appstoreconnect.env")) as handle:
        for line in handle:
            line = line.strip().removeprefix("export ")
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                values[key.strip()] = value.strip().strip("'\"")
    return values

_ENV = _env()
_KEY_ID = os.environ.get("PYTHILO_ASC_KEY_ID") or _ENV["ASC_KEY_ID"]
with open(f"{HOME}/.private_keys/AuthKey_{_KEY_ID}.p8") as handle:
    _KEY = handle.read()

def token():
    now = int(time.time())
    return jwt.encode({"iss": _ENV["ASC_ISSUER_ID"], "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"},
                      _KEY, algorithm="ES256", headers={"kid": _KEY_ID, "typ": "JWT"})

def call(method, path, body=None, raw=False):
    url = path if path.startswith("https://") else f"https://api.appstoreconnect.apple.com{path if path.startswith('/v') else '/v1' + path}"
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method)
    request.add_header("Authorization", f"Bearer {token()}")
    if data is not None:
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=120, context=_SSL) as response:
            text = response.read()
            return text if raw else (json.loads(text) if text else None)
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", "replace")
        raise RuntimeError(f"{method} {path} -> {error.code}\n{detail[:3000]}") from None

if __name__ == "__main__":
    body = json.loads(sys.argv[3]) if len(sys.argv) > 3 else None
    print(json.dumps(call(sys.argv[1], sys.argv[2], body), indent=1)[:20000])
