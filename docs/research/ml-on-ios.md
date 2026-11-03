# Machine learning on the device: where it stands

Plan sections 19 and 20, gates P0-F and P0-G. Checked on 3 November 2026.

## No ML wheels exist for iOS and CPython 3.14

Pythilo installs compiled packages only as iOS wheels (PEP 730), from PyPI or
BeeWare's channel. None of these has one for cp314:

| Package | PyPI | BeeWare channel |
| --- | --- | --- |
| torch | none (Pythilo builds its own, below) | none |
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

Done on 3 November 2026: PyTorch 2.15.0, built from the upstream source by
[torch-ios](https://github.com/sergii-ziborov/torch-ios), which Pythilo uses at a
pinned commit through `scripts/build-torch.sh`.

PyTorch treats every iOS target as "mobile" (no autograd, no Python bindings), so
torch-ios carries one patch that keeps the desktop build while cross-compiling:
everything native is force-loaded into a single `torch/_C` module (iOS loads native
code only as frameworks, and `embed-python.sh` makes one per extension module), which
links `Python.framework` and Accelerate (BLAS and LAPACK). Host-side generators
(protoc for ONNX, SLEEF's) are built for the Mac first. Built for iOS 13.0 (device)
and 14.0 (simulator), like the other native modules.

| | |
| --- | --- |
| Wheel | about 50 MB; `torch/_C` 115 MB installed, about 175 MB with the Python side |
| Dependencies | sympy, mpmath, networkx, jinja2, fsspec, filelock (pure Python) |
| Checked | simulator, in `RuntimeGateTests`: training, NumPy interop, linalg, fft, conv, `torch.func`, `torch.jit`, DataLoader, float16 and bfloat16, save and load |
| Not there | MPS and CUDA, `torch.compile` (no compiler or JIT on iOS), DataLoader workers and `torch.distributed` (one process) |

A physical iPhone has not run it yet.

## P0-F: the route that can work

Run models through the operating system instead of a Python framework:

1. Train or convert on a computer (PyTorch or anything else, then coremltools).
2. Ship the `.mlpackage` in the project.
3. A small native bridge in the app loads it with Core ML and runs it from
   Python, with the compute units chosen per run (CPU, GPU, Neural Engine), and
   returns the outputs as NumPy arrays plus the measured time.

Built as `pythilo.coreml` (`Pythilo/Runtime/CoreMLBridge.swift`, reached from
Python through `_pythilo.call`): `load()`, `predict()` with NumPy arrays,
`devices()`, `benchmark()` over cpu, gpu, ane and all, and a sample convolution
model. On the simulator Core ML reports a CPU and a GPU and no Neural Engine, so
`ane` falls back to the CPU there; the numbers that matter need a physical
iPhone or iPad.
