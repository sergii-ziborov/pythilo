# Machine learning on the device: where it stands

Plan sections 19 and 20, gates P0-F and P0-G. Checked on 3 November 2026.

## No ML wheels exist for iOS and CPython 3.14

Pythilo installs compiled packages only as iOS wheels (PEP 730), from PyPI or
BeeWare's channel. None of these has one for cp314:

| Package | PyPI | BeeWare channel |
| --- | --- | --- |
| torch | none | none |
| executorch | none (only yanked 0.1.x) | none |
| onnxruntime | none | none |
| scipy, scikit-learn | none | none |
| pandas, matplotlib | none | none |
| numpy, contourpy | none | yes, bundled (numpy) |
| pillow, kiwisolver | yes | n/a |

Checked with, for each package:

```sh
python3 -m pip download <name> --only-binary=:all: \
  --index-url https://pypi.org/simple \
  --extra-index-url https://pypi.anaconda.org/beeware/simple \
  --platform ios_18_0_arm64_iphoneos --platform ios_13_0_arm64_iphoneos \
  --python-version 3.14 --implementation cp --abi cp314 --abi abi3 --no-deps -d <dir>
```

## P0-G: full PyTorch build

Not attempted on this Mac, and the reason is concrete rather than a guess: a
PyTorch source build needs tens of gigabytes of build space and hours of compile
time, and this Mac had between 1 and 5 GB free while the work ran. PyTorch has
no iOS target for its Python package; its own iOS story was LibTorch-Lite, which
is C++ only and no longer developed, and ExecuTorch, which runs exported models
from C++ or Swift, not a Python `torch` module on the phone.

Result for the gate: unresolved. Nothing in Pythilo may say PyTorch runs on the
device.

## P0-F: the route that can work

Run models through the operating system instead of a Python framework:

1. Train or convert on a computer (PyTorch or anything else, then coremltools).
2. Ship the `.mlpackage` in the project.
3. A small native bridge in the app loads it with Core ML and runs it from
   Python, with the compute units chosen per run (CPU, GPU, Neural Engine), and
   returns the outputs as NumPy arrays plus the measured time.

The bridge is not built yet. Measuring the Neural Engine needs a physical
device: the simulator has none.
