#!/usr/bin/env python3
"""Writes Pythilo/Resources/Models/TinyConv.mlmodel, the sample model behind
pythilo.coreml.sample(): three strided 3x3 convolutions, a global average and
ten classes, about 126 million multiply-adds for one 3x224x224 image. Its
weights are random but seeded, so every build ships the same model.

Uses coremltools' NeuralNetworkBuilder, which needs no compiled extension.
Run it with a Python that has coremltools; the app does not need it.
"""

from pathlib import Path

import numpy as np
from coremltools.models import datatypes
from coremltools.models.neural_network import NeuralNetworkBuilder
from coremltools.models.utils import save_spec

OUT = Path(__file__).resolve().parent.parent / "Pythilo" / "Resources" / "Models" / "TinyConv.mlmodel"


def main():
    rng = np.random.default_rng(7)
    builder = NeuralNetworkBuilder([("image", datatypes.Array(3, 224, 224))], [("probabilities", datatypes.Array(10))])
    previous, channels = "image", 3
    for index, (width, stride) in enumerate(((32, 2), (64, 2), (128, 2)), 1):
        weights = rng.normal(0, np.sqrt(2 / (channels * 9)), (3, 3, channels, width)).astype(np.float32)
        builder.add_convolution(
            name=f"conv{index}", kernel_channels=channels, output_channels=width, height=3, width=3,
            stride_height=stride, stride_width=stride, border_mode="same", groups=1,
            W=weights, b=np.zeros(width, np.float32), has_bias=True,
            input_name=previous, output_name=f"conv{index}_out",
        )
        builder.add_activation(name=f"relu{index}", non_linearity="RELU", input_name=f"conv{index}_out", output_name=f"relu{index}_out")
        previous, channels = f"relu{index}_out", width
    builder.add_pooling(
        name="average", height=0, width=0, stride_height=1, stride_width=1, layer_type="AVERAGE",
        padding_type="VALID", input_name=previous, output_name="pooled", is_global=True,
    )
    builder.add_inner_product(
        name="classes", W=rng.normal(0, np.sqrt(1 / channels), (10, channels)).astype(np.float32),
        b=np.zeros(10, np.float32), input_channels=channels, output_channels=10, has_bias=True,
        input_name="pooled", output_name="logits",
    )
    builder.add_softmax(name="softmax", input_name="logits", output_name="probabilities")
    builder.spec.description.metadata.shortDescription = "Pythilo's sample: 3 convolutions and 10 classes, random seeded weights."
    builder.spec.description.metadata.author = "Pythilo"
    OUT.parent.mkdir(parents=True, exist_ok=True)
    save_spec(builder.spec, str(OUT))
    print(f"{OUT}: {OUT.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
