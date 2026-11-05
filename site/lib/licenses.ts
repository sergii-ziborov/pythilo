/**
 * Third-party components in the app and on this site, for the open-source licences page.
 * Python package versions must match runtime/requirements.lock and the licences their
 * .dist-info metadata declares; tests/legal.test.mjs checks the versions.
 */
export type Component = { name: string; version?: string; license: string; url: string; note?: string };

export const appRuntime: Component[] = [
  { name: "CPython", version: "3.14.10", license: "Python Software Foundation License", url: "https://docs.python.org/3/license.html" },
  { name: "Python-Apple-support (BeeWare)", version: "3.14-b14", license: "BSD 3-Clause", url: "https://github.com/beeware/Python-Apple-support" },
  { name: "OpenSSL", version: "3.5.9", license: "Apache License 2.0", url: "https://www.openssl.org/source/license.html", note: "Part of the Python support package" },
  { name: "libffi", version: "3.4.7", license: "MIT", url: "https://github.com/libffi/libffi/blob/master/LICENSE", note: "Part of the Python support package" },
  { name: "XZ Utils (liblzma)", version: "5.6.4", license: "0BSD", url: "https://tukaani.org/xz/", note: "Part of the Python support package" },
  { name: "bzip2", version: "1.0.8", license: "bzip2 licence (BSD-style)", url: "https://sourceware.org/bzip2/", note: "Part of the Python support package" },
  { name: "mpdecimal", version: "4.0.0", license: "BSD 2-Clause", url: "https://www.bytereef.org/mpdecimal/", note: "Part of the Python support package" },
  { name: "Zstandard", version: "1.5.7", license: "BSD 3-Clause (or GPLv2)", url: "https://github.com/facebook/zstd", note: "Part of the Python support package" },
  { name: "libgit2", version: "1.9.7", license: "GPLv2 with linking exception", url: "https://github.com/libgit2/libgit2/blob/main/COPYING", note: "Its bundled parts (llhttp, ntlmclient, PCRE2, xdiff) are listed in its COPYING file" },
  { name: "PyTorch", version: "2.15.0", license: "BSD 3-Clause", url: "https://github.com/pytorch/pytorch/blob/main/LICENSE", note: "Its third-party parts keep their own licences" },
  { name: "torch-ios", license: "BSD 3-Clause", url: "https://github.com/sergii-ziborov/torch-ios", note: "The build of PyTorch for iOS" },
  { name: "esbuild-wasm", version: "0.28.2", license: "MIT", url: "https://github.com/evanw/esbuild/blob/main/LICENSE.md" },
  { name: "Yjs", version: "13.6.33", license: "MIT", url: "https://github.com/yjs/yjs/blob/main/LICENSE", note: "With lib0 and y-protocols, for shared rooms" },
];

/** Bundled Python packages: name, version, licence as declared in the package metadata. */
export const pythonPackages: [string, string, string][] = [
  ["annotated-doc", "0.0.5", "MIT"],
  ["annotated-types", "0.8.0", "MIT"],
  ["anyio", "4.16.0", "MIT"],
  ["asgiref", "3.13.0", "BSD-3-Clause"],
  ["blinker", "1.9.0", "MIT"],
  ["certifi", "2026.10.23", "MPL-2.0"],
  ["charset_normalizer", "3.5.2", "MIT"],
  ["click", "8.5.0", "BSD-3-Clause"],
  ["django", "6.1.2", "BSD-3-Clause"],
  ["fastapi", "0.162.0", "MIT"],
  ["filelock", "4.2.7", "MIT"],
  ["flask", "3.1.3", "BSD-3-Clause"],
  ["fsspec", "2026.9.0", "BSD-3-Clause"],
  ["h11", "0.16.0", "MIT"],
  ["httpcore", "1.0.9", "BSD-3-Clause"],
  ["httpx", "0.28.1", "BSD-3-Clause"],
  ["idna", "3.20", "BSD-3-Clause"],
  ["iniconfig", "2.3.1", "MIT"],
  ["itsdangerous", "2.2.0", "BSD-3-Clause"],
  ["jedi", "0.20.1", "MIT"],
  ["jinja2", "3.1.6", "BSD-3-Clause"],
  ["markupsafe", "3.0.4", "BSD-3-Clause"],
  ["mpmath", "1.3.0", "BSD-3-Clause"],
  ["networkx", "3.7", "BSD-3-Clause"],
  ["numpy", "2.5.2.post1", "BSD-3-Clause AND 0BSD AND MIT AND Zlib AND CC0-1.0"],
  ["opentelemetry-api", "1.45.2", "Apache-2.0"],
  ["packaging", "26.3", "Apache-2.0 OR BSD-2-Clause"],
  ["parso", "0.8.7", "MIT"],
  ["pip", "26.2.2", "MIT"],
  ["pluggy", "1.7.0", "MIT"],
  ["pydantic", "2.14.2", "MIT"],
  ["pydantic_core", "2.50.2", "MIT"],
  ["pyflakes", "4.1.0", "MIT"],
  ["pygments", "2.21.0", "BSD-2-Clause"],
  ["pytest", "9.2.0", "MIT"],
  ["requests", "2.34.2", "Apache-2.0"],
  ["sqlparse", "0.6.1", "BSD-3-Clause"],
  ["starlette", "1.10.0", "BSD-3-Clause"],
  ["sympy", "1.14.0", "BSD-3-Clause"],
  ["torch", "2.15.0", "BSD-3-Clause"],
  ["typing-inspection", "0.4.4", "MIT"],
  ["typing_extensions", "4.16.0", "PSF-2.0"],
  ["urllib3", "2.8.0", "MIT"],
  ["uvicorn", "0.54.0", "BSD-3-Clause"],
  ["werkzeug", "3.1.9", "BSD-3-Clause"],
];

/** Licences of the website's runtime dependencies, by npm package name (or scope). */
export const siteLicenses: Record<string, string> = { pyodide: "MPL-2.0", "server-only": "MIT" };
export const siteLicense = (name: string) => siteLicenses[name] ?? "MIT";

export const bridgeComponents: Component[] = [
  { name: "MCP TypeScript SDK (@modelcontextprotocol)", version: "2.4.0", license: "Apache-2.0 (parts MIT and CC-BY-4.0)", url: "https://github.com/modelcontextprotocol/typescript-sdk" },
  { name: "Yjs, y-protocols, lib0", license: "MIT", url: "https://github.com/yjs/yjs" },
  { name: "Zod", version: "4.6.7", license: "MIT", url: "https://github.com/colinhacks/zod" },
];
