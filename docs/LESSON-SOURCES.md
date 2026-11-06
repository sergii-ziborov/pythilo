# Runtime-backed course expansion — 6 November 2026

The 52 lessons in courses 21–24 use the actual libraries bundled with Pythilo.
Pydantic is 2.14.2 in iOS and 2.12.5 in the pinned Pyodide distribution. Content
uses their common Pydantic 2 API and is executed in both runtimes. FastAPI and
HTTPX examples use in-memory ASGI or mock transports; no remote service is needed.

Primary API reference documentation:

- [Pydantic models](https://docs.pydantic.dev/latest/concepts/models/),
  [validators](https://docs.pydantic.dev/latest/concepts/validators/),
  [serialization](https://docs.pydantic.dev/latest/concepts/serialization/),
  [TypeAdapter](https://docs.pydantic.dev/latest/concepts/type_adapter/).
- [FastAPI testing](https://fastapi.tiangolo.com/tutorial/testing/) and
  [dependency overrides](https://fastapi.tiangolo.com/advanced/testing-dependencies/).
- [HTTPX transports](https://www.python-httpx.org/advanced/transports/).
- [pytest fixtures](https://docs.pytest.org/en/stable/how-to/fixtures.html),
  [capture](https://docs.pytest.org/en/stable/how-to/capture-stdout-stderr.html) and
  [logging](https://docs.pytest.org/en/stable/how-to/logging.html).
- Python 3.14 documentation for [mock](https://docs.python.org/3.14/library/unittest.mock.html),
  [TOML](https://docs.python.org/3.14/library/tomllib.html),
  [ElementTree](https://docs.python.org/3.14/library/xml.etree.elementtree.html),
  [ZIP](https://docs.python.org/3.14/library/zipfile.html),
  [gzip](https://docs.python.org/3.14/library/gzip.html),
  [struct](https://docs.python.org/3.14/library/struct.html),
  [Base64](https://docs.python.org/3.14/library/base64.html) and
  [HMAC](https://docs.python.org/3.14/library/hmac.html).

Exercises contain starters, worked solutions, three meaningful checks and three
topic-specific hints. Suite-generating pytest exercises test both correct and
broken implementations in fresh temporary modules. Their tests do not need
network access or host-installed pytest plugins.

All reading fences are Python code, including the traceback and pyproject
demonstrations: the former prints a caught real traceback, and the latter parses
TOML held in a Python string. Platform-specific reading blocks are identified
independently from exercise support in the website, so a runnable exercise stays
available even when a Django or PyTorch reading example requires the app.
