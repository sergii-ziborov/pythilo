"""The Python half of Pythilo. The app talks to it through `dispatch` and events."""

import json
import os
import signal
import sys

import _pythilo

from . import streams

bundle_root = ""
cache_root = ""


def emit_json(kind, payload):
    _pythilo.emit(kind, json.dumps(payload, ensure_ascii=False))


def boot(bundle, cache):
    global bundle_root, cache_root
    bundle_root = bundle
    cache_root = cache
    streams.install()
    from . import lanes, servers

    lanes.install()
    servers.install()

    packages = os.path.join(bundle, "app_packages")
    certificates = os.path.join(packages, "certifi", "cacert.pem")
    if os.path.exists(certificates):
        os.environ.setdefault("SSL_CERT_FILE", certificates)
        os.environ.setdefault("REQUESTS_CA_BUNDLE", certificates)

    # The app is one process, so nothing may end it from Python's side.
    os._exit = _refuse_process_exit
    signal.signal(signal.SIGINT, signal.default_int_handler)

    from . import runner

    runner.capture_baseline()
    emit_json(
        "ready",
        {
            "python": sys.version.split()[0],
            "implementation": sys.implementation.name,
            "platform": sys.platform,
        },
    )


def _refuse_process_exit(status=0):
    raise SystemExit(status)


def dispatch(text):
    from . import runner

    runner.run_job(json.loads(text))


# Terminal tabs only: Run, the debugger, notebooks, lessons and labs use the main thread.
_LANE_KINDS = {"shell"}


def dispatch_lane(lane, text):
    from . import runner

    job = json.loads(text)
    kind = job.get("kind")
    if kind not in _LANE_KINDS:
        print(f"pythilo: {kind} jobs run on the main thread only", file=sys.stderr)
        job = {**job, "kind": "shell", "line": "false"}
    runner.run_job(job, lane=lane)
