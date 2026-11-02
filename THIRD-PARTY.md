# Third-party components

| Component | Licence | Where |
| --- | --- | --- |
| CPython 3.14.10 | PSF License | `Vendor/Python.xcframework`, fetched by `scripts/fetch-python.sh` |
| Python-Apple-support (BeeWare) | BSD 3-Clause | Same package |
| OpenSSL, libFFI, XZ, BZip2, mpdecimal, Zstandard | Their own licences | Same package, listed in its `VERSIONS` |
| libgit2 1.9.7 | GPLv2 with linking exception | `Vendor/PythiloGitCore`, see its `COPYING` |
| Python packages in `runtime/requirements.lock` | Their own licences | Each keeps its licence in its `.dist-info` folder inside the app |

The editor, the Git core's build profile and the fold layout helpers come from
Crabrix and SharpRune, which have the same owner.
