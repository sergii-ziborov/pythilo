# Third-party components

| Component | Licence | Where |
| --- | --- | --- |
| CPython 3.14.10 | PSF License | `Vendor/Python.xcframework`, fetched by `scripts/fetch-python.sh` |
| Python-Apple-support (BeeWare) | BSD 3-Clause | Same package |
| OpenSSL, libFFI, XZ, BZip2, mpdecimal, Zstandard | Their own licences | Same package, listed in its `VERSIONS` |
| libgit2 1.9.7 | GPLv2 with linking exception | `Vendor/PythiloGitCore`, see its `COPYING` |
| Python packages in `runtime/requirements.lock` | Their own licences | Each keeps its licence in its `.dist-info` folder inside the app |
| pydantic-core 2.50.2 | MIT | Built from source by `scripts/build-pydantic-core.sh`; its licence ships in its `.dist-info` |
| PyTorch 2.15.0 | BSD 3-Clause (third-party parts under their own) | Built from source by `scripts/build-torch.sh` with [torch-ios](https://github.com/sergii-ziborov/torch-ios) (BSD 3-Clause); ships `torch/LICENSE.pytorch` and `torch/LICENSE.torch-ios` |
| esbuild-wasm 0.28.2 | MIT | `build/esbuild`, fetched by `scripts/vendor-packages.py`, with its `LICENSE.md` |
| Website: Next.js, React, CodeMirror, Yjs, Pyodide and others | Their own licences | `site/`, installed by pnpm; Pyodide's files are copied at build time |
| MCP bridge dependencies | Their own licences | `sdk/ThirdPartyNotices.txt` |

The editor, the Git core's build profile and the fold layout helpers come from
Crabrix and SharpRune, which have the same owner.
