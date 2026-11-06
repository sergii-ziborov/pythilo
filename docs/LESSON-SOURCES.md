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

## Advanced Python, ML and AI audit

The initial 308 path lessons gave broad foundations but did not establish senior
competence. The follow-up adds 74 lessons in seven courses (including six integrated
projects), plus 20 linked Labs: 12 ML and eight AI. Current totals are 382 path
lessons, 100 interview tasks and 72 native Labs. All checks are executable; local
experiments are explicitly distinguished from production deployments or clusters.

| Competency | Runnable practice | Evidence still required in real work |
| --- | --- | --- |
| Python language, ownership, interfaces | Existing deeper/typing/architecture courses; new resource unwinding, weak lifetimes, generators, descriptors and signature preservation | API/code review, compatibility decisions and profiling a real workload |
| Concurrency and failure recovery | Cancellation, bounded workers, context tokens, single-flight, queue draining and a retrying job-runner project | Multi-process coordination, overload, crash recovery and incident handling |
| Persistent services | SQLite outbox/inbox, replay conflicts, compare-and-swap, savepoints, migration rollback, keyset semantics and transactional importer | Real database isolation/query plans, rolling schema deployment, CI, package release, load/security testing |
| Honest ML evaluation | Group/time split, ROC/AP ties, calibration, Wilson/bootstrap/randomization, multiple comparisons, OOF and nested selection | Representative real data, independent evaluation, experiment design and peer review |
| Model development and operations | Real boosted stumps and ridge experiment; point-in-time joins, drift, conformal ranks, importance, cohorts, delayed outcomes and artifact identity | Dataset/version pipeline, real serving measurements, monitored canary and rollback |
| Deep-learning correctness | Actual PyTorch CPU microbatch gradients, padding masks, frozen statistics, mode restoration, checkpoint ownership, target shift and LoRA merge | GPU memory/performance, AMP, real DDP/FSDP collectives, cluster failure and exact resume |
| AI/LLM engineering | Existing tiny GPT/LoRA lessons plus permission-aware lexical retrieval, RRF, token context, citations, tool authority, approval identity, bounded execution and eval gates | Actual model-backed representative/adversarial evaluations, answer faithfulness, cost/latency, index rollout and observability |

The six integration projects test composed behavior, not just isolated formulas:
tenant-scoped event import, bounded/retrying jobs, train/select/test regression,
delayed-outcome monitoring, authorized lexical RAG retrieval and an approved tool
executor. Each includes a review rubric and states which guarantees it does not
provide. Finishing a course is not a certificate of seniority; the public
`/learn/senior/` page makes the remaining fieldwork explicit for all three tracks.

Primary references checked for the audit:

- [Python 3.14 task cancellation and structured concurrency](https://docs.python.org/3.14/library/asyncio-task.html),
  [queues and shutdown](https://docs.python.org/3.14/library/asyncio-queue.html),
  [SQLite transaction control](https://docs.python.org/3.14/library/sqlite3.html),
  [context managers](https://docs.python.org/3.14/library/contextlib.html).
- scikit-learn [leakage pitfalls](https://scikit-learn.org/stable/common_pitfalls.html),
  [cross-validation](https://scikit-learn.org/stable/modules/cross_validation.html),
  [metrics](https://scikit-learn.org/stable/modules/model_evaluation.html) and
  [probability calibration](https://scikit-learn.org/stable/modules/calibration.html).
  Exercises implement inspectable local reference algorithms; scikit-learn is not
  claimed to be bundled on iOS.
- PyTorch [DDP design](https://docs.pytorch.org/docs/2.15/notes/ddp.html) and
  [distributed checkpointing](https://docs.pytorch.org/docs/stable/distributed.checkpoint.html).
  The weighted local reduction lesson is explicitly not a cluster execution.
- [OWASP prompt injection](https://genai.owasp.org/llmrisk/llm01-prompt-injection/):
  separating roles or encoding evidence as JSON does not eliminate semantic prompt
  injection; authorization and approval checks remain outside the model.
- [Google SRE: implementing SLOs](https://sre.google/workbook/implementing-slos/):
  objectives, user-event denominators and error budgets inform the local burn-rate
  and rollout exercises, rather than universal automatic release claims.

## ML/AI systems projects — 6 November 2026

Courses 32–33 add 24 lessons with 24 linked Labs: 12 ML and 12 AI. Twelve are
composed projects with 4–5 independent check groups each. Model projects train
real NumPy ridge/logistic regressions, construct OOF stacking features, run nested
group selection and walk-forward evaluation, and test delayed-label rollout
state. Perturbation checks ensure held-out targets and inaccessible documents
cannot affect their own fitted predictions or authorized retrieval scores.

The AI projects implement BM25, immutable index-batch/CAS/tombstone handling,
context packing with exact citation spans, approved local tool DAG execution,
bounded continuous-batching simulation and paired release evidence. RAG receives
a saved provider-output fixture; it does not claim live LLM inference or semantic
faithfulness. The serving scheduler is explicitly a discrete simulation. Exact
approval hashes are identities in a trusted controller-provided allowlist, not
permission created by hashing. Local copied-state publication does not claim
durable distributed exactly-once effects.

Large project replays follow the orchestration function so the complete scenario
fits the browser's 180-frame budget. Helpers still execute; independent checks
exercise full datasets and failure cases. Reading blocks remain standalone
Python programs. All new exercises use stdlib or the NumPy already bundled in
both runtimes, with no credentials, remote model or new native package required.

Primary references:

- scikit-learn [nested versus non-nested cross-validation](https://scikit-learn.org/stable/auto_examples/model_selection/plot_nested_cross_validation_iris.html),
  [cross-validation](https://scikit-learn.org/stable/modules/cross_validation.html)
  and [probability calibration](https://scikit-learn.org/stable/modules/calibration.html).
- Stanford's [Introduction to Information Retrieval: ranked evaluation](https://nlp.stanford.edu/IR-book/pdf/08eval.pdf)
  informs the graded NDCG exercise; tokenization and BM25 constants are stated in
  the runnable contract rather than implied to match an external search engine.
- [OWASP RAG security guidance](https://cheatsheetseries.owasp.org/cheatsheets/RAG_Security_Cheat_Sheet.html)
  informs access filtering, versioned provenance and the distinction between
  digest consistency, instruction trust and semantic answer support.

## PyTorch and transformer Labs

The `pytorch-training` and `transformer-engineering` courses add 18 lessons with
18 native Labs, including six composed projects. Solutions are original,
self-contained CPU programs using the bundled PyTorch 2.15 runtime. All 79 check
groups execute forward computations, autograd, optimizer updates, state ownership
or inference from exported artifacts. Training traces use four small updates;
checks run longer trajectories and compare independent evidence.

Projects train a nonlinear classifier with a validation-selected owned checkpoint,
continue AdamW sampling/dropout exactly within the same CPU runtime, learn and
merge a low-rank linear adapter, audit a causal decoder block, train a tiny tied
embedding language model and classify padded variable-length sequences. No
downloaded pretrained weights, GPU, remote inference or distributed training is
claimed. The synthetic fixtures establish the listed behavior rather than useful
language understanding or representative deployment quality. Browser pages mark
these Labs App required; existing compatible Labs continue running in Pyodide.

Primary references checked for this expansion:

- PyTorch [scaled dot-product attention](https://docs.pytorch.org/docs/main/generated/torch.nn.functional.scaled_dot_product_attention.html):
  participation-mask semantics, causal alignment and explicit dropout policy.
- PyTorch [saving and loading models](https://docs.pytorch.org/tutorials/beginner/saving_loading_models.html):
  model and optimizer state ownership; this course separately captures CPU RNG
  and a fixed data-stream identity for its bounded continuation contract.
- [RoFormer](https://arxiv.org/abs/2104.09864): rotary position geometry. The Lab
  explicitly chooses adjacent coordinate pairs and checks common-offset behavior.
- [LoRA](https://arxiv.org/abs/2106.09685): frozen-base low-rank updates. The local
  project states its scaling and does not claim a pretrained-model fine-tune.

The shared `lab-topics.json` assigns every native Lab to exactly one topic in its
section. Native and web catalogs use those same assignments, with expandable topic
groups, concept search and visible runtime requirements on the site.
