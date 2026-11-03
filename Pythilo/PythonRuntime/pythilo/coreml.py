"""Core ML from Python: load a model, run it on the CPU, the GPU or the Neural
Engine, and time it.

PyTorch does not run on an iPhone or iPad, and nothing else reaches the Neural
Engine: Core ML is the way in. Train on a computer, convert with coremltools,
copy the .mlpackage or .mlmodel into the project, and run it here:

    import numpy
    from pythilo import coreml

    model = coreml.load("classifier.mlpackage", compute="ane")
    out = model.predict({"image": numpy.zeros((3, 224, 224), "float32")})
    print(out["probabilities"], model.last_milliseconds)

`compute` is "all" (Core ML chooses), "cpu", "gpu" or "ane" (CPU and Neural
Engine). Where a unit is missing, as on the simulator, Core ML falls back to the
CPU; `devices()` says what is really there.
"""

import json
import os
import statistics

import numpy

import _pythilo

COMPUTE = ("cpu", "gpu", "ane", "all")
_DTYPES = {"float32": numpy.float32, "float16": numpy.float16, "float64": numpy.float64, "int32": numpy.int32}


def _call(header, blob=b""):
    head, _, body = _pythilo.call(json.dumps(header).encode() + b"\n" + blob).partition(b"\n")
    return json.loads(head), body


def devices():
    """The compute devices Core ML reports, and whether one is a Neural Engine."""
    return _call({"op": "devices"})[0]


class Model:
    """A loaded model. Use it in a with block, or call close() when done."""

    def __init__(self, path, compute="all"):
        if compute not in COMPUTE:
            raise ValueError(f"compute is one of {', '.join(COMPUTE)}")
        target = path if path.startswith("sample:") else os.path.abspath(path)
        info, _ = _call({"op": "load", "path": target, "compute": compute})
        self.id = info["id"]
        self.path = path
        self.compute = compute
        self.inputs = info["inputs"]
        self.outputs = info["outputs"]
        self.load_milliseconds = info["milliseconds"]
        self.last_milliseconds = None

    def predict(self, inputs):
        """Runs once. Takes and returns NumPy arrays, by feature name."""
        specs, chunks, offset = [], [], 0
        for name, value in inputs.items():
            array = numpy.ascontiguousarray(value)
            if array.dtype.name not in _DTYPES:
                array = array.astype(numpy.float32)
            data = array.tobytes()
            specs.append({"name": name, "dtype": array.dtype.name, "shape": list(array.shape), "offset": offset, "length": len(data)})
            chunks.append(data)
            offset += len(data)
        info, body = _call({"op": "predict", "model": self.id, "inputs": specs}, b"".join(chunks))
        self.last_milliseconds = info["milliseconds"]
        result = dict(info.get("scalars", {}))
        for spec in info["outputs"]:
            raw = body[spec["offset"] : spec["offset"] + spec["length"]]
            result[spec["name"]] = numpy.frombuffer(raw, dtype=_DTYPES[spec["dtype"]]).reshape(spec["shape"]).copy()
        return result

    def close(self):
        _call({"op": "unload", "model": self.id})

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()

    def __repr__(self):
        return f"<coreml.Model {self.path!r} on {self.compute}>"


def load(path, compute="all"):
    return Model(path, compute)


def sample(compute="all"):
    """Pythilo's sample model: three convolutions over a 3x224x224 image and ten
    classes, about 126 million multiply-adds. Its weights are random."""
    return Model("sample:tiny-conv", compute)


def benchmark(path="sample:tiny-conv", inputs=None, compute=COMPUTE, runs=10):
    """Times one model on each compute choice, the first run apart, and checks
    each choice gives the CPU's answer. One dict per choice."""
    rows, reference = [], None
    for unit in compute:
        with Model(path, unit) as model:
            if inputs is None:
                generator = numpy.random.default_rng(0)
                inputs = {spec["name"]: generator.standard_normal(spec["shape"]).astype("float32") for spec in model.inputs if "shape" in spec}
            first = model.predict(inputs)
            first_ms = model.last_milliseconds
            times = []
            for _ in range(runs):
                model.predict(inputs)
                times.append(model.last_milliseconds)
            key = model.outputs[0]["name"]
            answer = first[key].astype("float32")
            if reference is None:
                reference = answer
            rows.append({
                "compute": unit,
                "load_ms": model.load_milliseconds,
                "first_ms": first_ms,
                "median_ms": statistics.median(times),
                "max_difference": float(numpy.max(numpy.abs(answer - reference))),
            })
    return rows


def report(rows):
    """Prints benchmark() rows as a table narrow enough for a phone."""
    print("ms:   load  first median  vs cpu")
    for row in rows:
        print(f"{row['compute']:<4}{row['load_ms']:>7.1f}{row['first_ms']:>7.2f}{row['median_ms']:>7.2f}{row['max_difference']:>8.0e}")
