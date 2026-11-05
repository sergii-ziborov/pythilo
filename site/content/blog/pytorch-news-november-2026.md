---
title: "PyTorch and neural networks in November 2026: 2.15, the end of TorchScript, and models that fit in your pocket"
description: "PyTorch 2.15 is out, TorchScript is on its way out, ExecuTorch is now part of PyTorch core, and open models keep getting sparser and smaller. A sourced look at a year of PyTorch releases and at where neural network design is going."
date: 2026-11-04
author: Pythilo
cover: /blog/pytorch-news-november-2026/cover.png
coverAlt: "Abstract illustration: a network of glowing blue, green and yellow nodes narrows upward into a flame shape, fed from below by five stacks of translucent cubes."
tags: PyTorch, Machine learning, On-device AI, Models
---

PyTorch 2.15 came out on 28 October 2026, the eighth feature release since 2.8 in August 2025. Each of these releases is a few thousand commits. This one alone has 3,117 commits from 583 contributors. Taken together, they change what PyTorch is: less a research framework you script in Python, more a compiler, a deployment toolchain and a hardware layer that runs from data-centre GPUs down to phones and microcontrollers.

This post covers what changed in PyTorch between 2.8 and 2.15, where `torch.compile` and `torch.export` stand now that TorchScript is being retired, what happened in on-device inference, and which ideas are shaping the newest open models. Every version, date and figure comes from an official source, listed at the end. Where something isn't settled, we say so.

## A year of releases, 2.8 to 2.15

PyTorch now ships a feature release about every two months. Here are the headlines, with the dates on the official GitHub releases:

- **2.8, 6 August 2025.** Hierarchical compilation in `torch.compile`, an Inductor CUTLASS backend, and the first piece of a stable C++ ABI (`torch::stable::Tensor`). `torch.export` started defaulting to `strict=False`. The CUDA 12.8 and 12.9 builds dropped Maxwell and Pascal GPUs.
- **2.9, 15 October 2025.** The minimum Python became 3.10, and Python 3.14, including the free-threaded 3.14t, arrived as a preview. A stable libtorch ABI for C++ and CUDA extensions, symmetric memory for multi-GPU kernels, and the option to make `torch.compile` either error or continue at a graph break. The ONNX exporter switched to the `torch.export` path by default.
- **2.10, 21 January 2026.** `torch.compile` gained Python 3.14 support (3.14t experimental), plus a new `varlen_attn()` for ragged and packed sequences and a DebugMode for chasing numerical bugs. `torch.jit` started emitting deprecation warnings.
- **2.11, 23 March 2026.** FlexAttention gained a FlashAttention-4 backend on Hopper and Blackwell GPUs, Apple Silicon got a large batch of new MPS operators, and the PyPI wheels moved to CUDA 13.0. PT2E quantization moved out of core into torchao.
- **2.12, 13 May 2026.** Batched `linalg.eigh` on CUDA became up to 100 times faster, plus a new `torch.accelerator.Graph` API and MX quantization formats in `torch.export.save`.
- **2.13, 8 July 2026.** FlexAttention came to Apple Silicon, along with a prototype CuTeDSL backend for Inductor and `nn.LinearCrossEntropyLoss`, which uses up to four times less peak memory. Linux wheels for Python 3.15 and 3.15t appeared.
- **2.14, 2 September 2026.** NVGEMM (CuTeDSL CUTLASS kernels in Inductor, including NVFP4), `torch.switch` for multi-way branching, and native linear algebra on Apple Silicon. TorchScript APIs now raise visible `FutureWarning`s.
- **2.15, 28 October 2026.** Covered in the next section.

There are three trends here. Python support moves forward fast: 3.14 went from preview to fully supported within the year. NVIDIA's newest GPUs get low-precision kernels almost as soon as they ship. And Apple Silicon has gone from an afterthought to a platform that gets real work in nearly every release.

## What is in PyTorch 2.15

The 2.15 release blog lists these highlights:

- **A rewritten NCCL backend is now the default** for every `nccl` process group. It includes a flight recorder that writes a post-mortem to disk when a collective hangs. `TORCH_DIST_USE_NCCL2=0` or the `nccl-legacy` backend name bring back the old one.
- **One-sided transports** for `torch.distributed`, with NIXL as the first backend.
- **FSDP2 and pipeline parallelism** gain finer control over memory and communication. For example, MoE router gates and norm weights can stay in fp32 while the rest of the model trains in bf16.
- **Faster 4-bit (NVFP4) decoding** on NVIDIA Blackwell GPUs.
- **Apple Silicon gets FP8 and faster decoding**: `float8_e4m3fn` and `_scaled_mm` on MPS, a new `grouped_mm` with a decode fast path, and public `torch.mps.Stream` APIs.
- **Broader platform support**: CUDA 13.2 is the default wheel with CUDA 13.4 alongside it, ROCm 10.0 wheels are added, and Intel GPUs get simpler SYCL kernels.

Two Apple Silicon numbers from the blog stand out. The new MPS `grouped_mm` gives **1.32 to 1.34 times higher mixture-of-experts decode throughput on an M3 Ultra**, and QR decomposition of a 512 by 512 matrix went **from about 7 seconds to 1.5 milliseconds** after the solvers were rewritten. The second number says less about how fast the new code is than about how far behind some MPS paths had been.

The deprecations matter just as much:

- **Python 3.10 is no longer supported.** PyTorch 2.15 supports Python 3.11 to 3.15, including the free-threaded 3.14t and 3.15t, and `torch.compile` now works on Python 3.15.
- **macOS 14 is no longer supported for MPS.** GPU acceleration on a Mac now needs macOS 15 or newer.
- The `nccl` backend name now selects the rewritten backend, and FSDP2 handles gradient dtypes differently when `reduce_dtype=None`.

If you maintain a training setup, read the "Deprecations and Backwards-Incompatible Changes" section of the release notes before you upgrade.

## Compile and export: the end of TorchScript

For most of PyTorch's history, getting a model out of Python meant TorchScript, through `torch.jit.script` or `torch.jit.trace`. That era is ending. The documentation now says "TorchScript is deprecated, please use torch.export instead". PyTorch 2.10 added deprecation warnings, and 2.14 turned them into visible `FutureWarning`s. TorchScript hasn't been removed: 2.15 still fixes `torch.jit` bugs. But there's no longer a good reason to start a new project on it.

What replaces it is two tools with clearly separate jobs:

- `torch.compile` speeds up a model while it still runs in Python. It captures the model's graph as the code runs, compiles it with Inductor into fused Triton or C++ kernels, and drops back to ordinary Python where it has to (a "graph break"). Since 2.9 you can choose whether a graph break is an error or should be resumed.
- `torch.export` captures a whole model ahead of time as one clean graph with no Python left in it. That graph feeds the ONNX exporter (the default path since 2.9), AOTInductor, which compiles an exported model into a shared library for deployment without Python, and ExecuTorch for phones and embedded devices.

```python
import torch

class TinyNet(torch.nn.Module):
    def __init__(self):
        super().__init__()
        self.layers = torch.nn.Sequential(torch.nn.Linear(4, 16), torch.nn.ReLU(), torch.nn.Linear(16, 3))

    def forward(self, x):
        return self.layers(x)

model = TinyNet().eval()
example = (torch.randn(1, 4),)

fast = torch.compile(model)                      # still Python, faster kernels
program = torch.export.export(model, example)    # a full graph, ready to deploy
print(program.graph_module.code)
```

2.15 also makes `torch.compiler.precompile` a module with `capture()` and `load()`, so compiled artefacts can be saved and reused across processes. And it adds thread-based compile workers for free-threaded Python. That's a small detail, but it shows the free-threading work in CPython reaching real libraries.

## Neural networks on the device

The biggest change for anyone shipping models to phones happened at the PyTorch Conference Europe in Paris, on 7 and 8 April 2026: **ExecuTorch became part of PyTorch core.** Meta created ExecuTorch, PyTorch's runtime for phones, headsets and microcontrollers. Version 1.0 reached general availability in October 2025 (the GitHub release is dated 18 October, the blog post 22 October).

![Illustration: a smartphone whose screen shows a small glowing network of nodes wired down to a chip, with a crossed-out Wi-Fi symbol in the corner to show it works offline.](/blog/pytorch-news-november-2026/on-device.webp "On-device inference: the model, its weights and the data stay on the phone. ExecuTorch, Core ML and MLX are the main routes on Apple hardware.")

Since 1.0, ExecuTorch has moved about as fast as PyTorch itself. The latest release is 1.5.1, from 23 September 2026. Along the way:

- **1.0** brought multimodal LLM APIs for C++, Java, Objective-C and Swift, LoRA adapters that share base weights, and 4-bit HQQ quantization.
- **1.1** added an experimental Metal backend.
- **1.2** (1 April 2026) deprecated the MPS backend, saying it "will be removed in a future release (v1.4.0)", ported int4 GEMM kernels from MLX to the Metal backend, and added export for the 0.8B, 2B and 4B Qwen3.5 models.
- **1.3** added an MLX delegate.
- **1.5** (16 September 2026) added linkable Core ML and MLX libraries for Apple frameworks and Swift Package Manager, BF16 support in XNNPACK, Gemma 4 text models on Qualcomm, and Qwen3.5 MoE in its LLM workflows.

On Apple hardware, then, the direction is clear. Core ML and MLX are the delegates ExecuTorch hands work to, Metal handles what they don't, and the old MPS delegate is on its way out.

Apple's own platform changed too. Apple's 2025 foundation model report describes its on-device model as about 3 billion parameters, compressed to 2 bits per weight with quantization-aware training. At WWDC26 Apple introduced **Core AI**, which it calls "the best way to bring your own models on-device", a new framework with a Swift API for loading, specializing and running models with no server. The Foundation Models framework now works with any language model provider that conforms to its protocol, and Apple names Claude and Gemini as examples. It also takes images as input, and gives apps with fewer than 2 million first-time downloads access to Apple's model on Private Cloud Compute. MLX, Apple's open-source array framework, gains Metal 4, GPU Neural Accelerator support and training across several Macs over Thunderbolt.

### Where Pythilo fits

Pythilo runs PyTorch on the iPhone and iPad differently from the routes above. It doesn't ship an exported model: it ships **the full PyTorch 2.15 library**, autograd and Python bindings included. We build it from source for iOS with the open-source [torch-ios](https://github.com/sergii-ziborov/torch-ios) project, against the app's embedded CPython 3.14. It runs on the CPU, with matrix maths through Apple's Accelerate framework. That makes it slower than an exported model on the Neural Engine, but it can do something no export can: train. The machine learning lessons build and train real networks offline on the device, with the same code you would write on a laptop.

To be clear about the limits: Pythilo has no MPS backend, no `torch.compile` and no DataLoader workers, and its PyTorch has been tested on the iOS Simulator (a conformance suite that matches a Mac reference build on 203 groups of operations) but not yet on a physical iPhone. ExecuTorch has no iOS wheel for CPython 3.14, so it isn't in the app. To run a model on the Neural Engine, Pythilo has a small `pythilo.coreml` module that runs Core ML models from Python on the CPU, the GPU or the Neural Engine, with timings.

## The PyTorch Foundation grows up

The PyTorch Foundation, part of the Linux Foundation, now hosts much more than PyTorch:

- **vLLM** and **DeepSpeed** joined on 7 May 2025, when the foundation became an umbrella foundation.
- **Ray** joined on 22 October 2025.
- **Helion**, Meta's Python-embedded language for writing fast ML kernels, and **Safetensors**, Hugging Face's safe model file format, joined in Paris in April 2026.

Safetensors in particular is worth knowing about if you download models. Unlike pickle-based checkpoints, a Safetensors file can't run code when you load it.

The conferences grew as well. PyTorch Conference 2025 in San Francisco (22 and 23 October 2025) had more than 3,400 attendees. The first PyTorch Conference Europe in Paris drew more than 600. A China edition took place in Shanghai on 8 and 9 September 2026, and PyTorch Conference North America took place in San Jose on 20 and 21 October 2026. Mark Collier became the foundation's executive director in February 2026.

## Where model architecture is going

The open models of 2025 and 2026 have a lot in common. Four ideas keep coming up.

![Diagram-style illustration: a row of blue squares enters a round router on the left, which fans out to a grid of dark expert blocks; only two paths, one yellow and one blue, light up and pass through one expert each before joining a round node that outputs a row of green squares.](/blog/pytorch-news-november-2026/mixture-of-experts.webp "Mixture of experts: a router sends each token to a few experts, so a model can hold many parameters but use only a small fraction of them per token.")

### Mixture of experts everywhere

In a mixture-of-experts (MoE) layer, a small router sends each token to a few "expert" feed-forward networks out of many, so a model can be very large in total but cheap to run per token. Almost every large open model now uses it:

- **Llama 4** (Meta, 5 April 2025): Scout has 17B active and 109B total parameters with 16 experts; Maverick has 17B active and 400B total with 128 experts.
- **gpt-oss** (OpenAI, August 2025, Apache 2.0): gpt-oss-120b has 117B parameters with 5.1B active and fits on a single 80 GB GPU; gpt-oss-20b has 21B with 3.6B active and runs in 16 GB of memory.
- **Qwen3.5** (Alibaba, February 2026, Apache 2.0): the flagship Qwen3.5-397B-A17B has 397B total and 17B active parameters, with 512 experts, of which 10 routed plus 1 shared are active for each token.
- **DeepSeek V4** (April 2026, MIT licence): V4-Pro has 1.6 trillion total and 49B active parameters, and V4-Flash has 284B and 13B, both with a 1-million-token context.

The ratio is the thing to notice: 17B of 397B, 49B of 1.6T. Active parameters set the cost per token; total parameters set how much the model knows.

### Attention gets cheaper

Standard attention costs grow with the square of the sequence length, and the KV cache grows with every token. Several designs push back on that:

- **Hybrid linear attention.** According to its model card, Qwen3.5 stacks blocks of three Gated DeltaNet layers (a linear-attention variant with a fixed-size state) followed by one full gated-attention layer. Most layers then don't need a growing cache. ExecuTorch has added gated delta rule kernels to run this kind of layer on devices.
- **Sliding-window attention.** Gemma 4 and gpt-oss alternate local layers, which only see a window of recent tokens, with global layers.
- **Compressed attention.** DeepSeek V4's model card describes a hybrid of compressed sparse attention and heavily compressed attention, aimed at long contexts.

### Weights in fewer bits

Low precision is now part of how models are trained and released, not something added afterwards. gpt-oss ships its MoE weights in MXFP4, a 4-bit format. Apple's on-device model uses 2-bit weights trained with quantization in the loop. And the PyTorch releases above keep adding FP8 and FP4 paths: NVFP4 on Blackwell, MX formats in `torch.export.save`, FP8 on Apple Silicon in 2.15.

### Small models that run offline

At the other end, **Gemma 4** (Google, 2 April 2026, Apache 2.0) comes in four sizes. E2B and E4B are "effective 2B and 4B" models with a 128K context, which Google says run completely offline on phones, a Raspberry Pi or a Jetson Orin Nano. A 26B mixture-of-experts model and a 31B dense model go up to 256K. Gemma 4 support also showed up quickly in ExecuTorch's Qualcomm backend. Small open models like these are what make on-device language models practical, rather than just a demo.

## What this means if you are learning

You don't need any of the above to start learning neural networks. A two-layer network trained on a toy dataset uses the same `nn.Module`, `autograd` and optimizer loop that every model above is built from. That's the code Pythilo's machine learning course has you write and run on an iPhone.

Once you're past the basics, the year's changes suggest what to learn next, roughly in this order:

1. **Attention**, and how a KV cache works.
2. **Mixture of experts**, and why active parameters matter.
3. **Quantization**, and what FP8 or 4-bit weights trade away.
4. `torch.export`, now that TorchScript is going away.

Pythilo's "language models from the inside" course builds the first of these step by step. The rest are well covered by the PyTorch documentation and the model cards linked below.

## Sources

- [PyTorch releases](https://github.com/pytorch/pytorch/releases), GitHub (v2.8.0 to v2.15.0)
- [PyTorch 2.8 release blog](https://pytorch.org/blog/pytorch-2-8/)
- [PyTorch 2.9 release blog](https://pytorch.org/blog/pytorch-2-9/)
- [PyTorch 2.10 release blog](https://pytorch.org/blog/pytorch-2-10-release-blog/)
- [PyTorch 2.11 release blog](https://pytorch.org/blog/pytorch-2-11-release-blog/)
- [PyTorch 2.12 release notes](https://github.com/pytorch/pytorch/releases/tag/v2.12.0), GitHub
- [PyTorch 2.13 release blog](https://pytorch.org/blog/pytorch-2-13-release-blog/)
- [PyTorch 2.14 release blog](https://pytorch.org/blog/pytorch-2-14-release-blog/)
- [PyTorch 2.15 release blog](https://pytorch.org/blog/pytorch-2-15-release-blog/) and [release notes](https://github.com/pytorch/pytorch/releases/tag/v2.15.0)
- [AOTInductor documentation](https://docs.pytorch.org/docs/stable/torch.compiler_aot_inductor.html)
- [ExecuTorch releases](https://github.com/pytorch/executorch/releases), GitHub, including [v1.2.0](https://github.com/pytorch/executorch/releases/tag/v1.2.0) and [v1.5.0](https://github.com/pytorch/executorch/releases/tag/v1.5.0)
- [Introducing ExecuTorch 1.0](https://pytorch.org/blog/introducing-executorch-1-0/), PyTorch blog
- [PyTorch Conference Europe 2026 recap](https://pytorch.org/blog/pytorch-conference-europe-2026-a-landmark-moment-for-open-source-ai-in-paris/), PyTorch blog
- [ExecuTorch becomes part of PyTorch core](https://pytorch.org/blog/executorch-becomes-part-of-pytorch-core/), PyTorch blog
- [PyTorch Foundation welcomes vLLM and DeepSpeed](https://pytorch.org/blog/press-release-pytorch-foundation-expands-welcomes-projects-vllm-deepspeed/), PyTorch blog
- [PyTorch Foundation welcomes Ray](https://pytorch.org/blog/pytorch-foundation-welcomes-ray-to-deliver-a-unified-open-source-ai-compute-stack/), PyTorch blog
- [Safetensors joins the PyTorch Foundation](https://www.linuxfoundation.org/press/pytorch-foundation-announces-safetensors-as-newest-contributed-project-to-secure-ai-model-execution), Linux Foundation
- [PyTorch Conference 2025 recap](https://pytorch.org/blog/pytorch-conference-2025-recap/) and [PyTorch Conference North America 2026](https://pytorch.org/blog/pytorch-conference-north-america-2026-accelerating-open-intelligence-together/), PyTorch blog
- [The PyTorch Foundation: the next chapter, together](https://pytorch.org/blog/pytorch-foundation-the-next-chapter-together/), PyTorch blog
- [Apple Intelligence Foundation Language Models, 2025 updates](https://machinelearning.apple.com/research/apple-foundation-models-2025-updates), Apple Machine Learning Research
- [WWDC26 machine learning guide](https://developer.apple.com/wwdc26/guides/machine-learning/), Apple Developer
- [The Llama 4 herd](https://ai.meta.com/blog/llama-4-multimodal-intelligence/), Meta AI
- [gpt-oss repository](https://github.com/openai/gpt-oss), OpenAI on GitHub
- [Qwen3.5-397B-A17B model card](https://huggingface.co/Qwen/Qwen3.5-397B-A17B), Hugging Face
- [DeepSeek-V4-Pro model card](https://huggingface.co/deepseek-ai/DeepSeek-V4-Pro), Hugging Face
- [Gemma 4 announcement](https://blog.google/innovation-and-ai/technology/developers-tools/gemma-4/), Google
- Pythilo's PyTorch build: [torch-ios](https://github.com/sergii-ziborov/torch-ios), and the project's README and status notes
