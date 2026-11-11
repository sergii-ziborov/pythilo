"""Tells the app when a program starts listening, so it can offer to open the site.

Django's runserver, Flask's werkzeug and Uvicorn's asyncio all end in
socket.listen(), so this sees every server whatever it prints.
"""

import socket

from . import emit_json

_listen = socket.socket.listen


def _announce(self, *args):
    result = _listen(self, *args)
    try:
        if self.type == socket.SOCK_STREAM and self.family in (socket.AF_INET, socket.AF_INET6):
            host, port = self.getsockname()[:2]
            from . import lanes

            emit_json("server_listening", {"host": host, "port": port, "lane": lanes.current_lane()})
    except OSError:
        pass
    return result


def install():
    socket.socket.listen = _announce
