/** Evidence-oriented paths. Course completion does not certify a job level. */
export const seniorPaths = [
  {
    id: 'python', title: 'Senior Python engineering',
    outcome: 'Explain ownership, preserve invariants through failures, and review a service beyond its happy path.',
    prerequisites: ['deeper', 'testing', 'architecture', 'async'],
    courses: ['python-runtime', 'python-systems', 'pydantic', 'fastapi-httpx', 'testing-practice'],
    projects: ['project-ledger', 'project-async-worker'],
    review: ['Demonstrate rollback, conflicting replays and tenant isolation using database state.', 'Explain task lifetime, bounded creation, cancellation and which effects are safe to retry.', 'Review API compatibility, typing, profiling, security boundaries, operational metrics and recovery.'],
    fieldwork: ['Operate a multi-process service with a real database, schema rollout, load tests and failure injection.', 'Build and review a package and CI pipeline, investigate an incident, and document a design tradeoff with another engineer.'],
  },
  {
    id: 'ml', title: 'Senior machine-learning engineering',
    outcome: 'Produce an auditable experiment, justify uncertainty and decide whether a model has enough evidence for a controlled rollout.',
    prerequisites: ['data', 'math', 'ml', 'ml-practice', 'ml-evaluation'],
    courses: ['ml-statistics', 'ml-production', 'deep-learning-practice', 'ml-systems', 'pytorch-training'],
    projects: ['project-ml-pipeline', 'project-delayed-monitor', 'project-ridgeworkflow', 'project-nestedridge', 'project-walkforward', 'project-stackingproject', 'project-logisticproject', 'project-rolloutmonitor', 'project-torchmlp', 'project-torchresume', 'project-torchlora'],
    review: ['Separate group/time splits, preprocessing, calibration, model selection and final evaluation.', 'Defend baselines, uncertainty, error costs, subgroup results and data availability at prediction time.', 'Reproduce the artifact and explain monitoring, delayed labels, drift, serving budgets and rollback.'],
    fieldwork: ['Run a real dataset pipeline with versioned data, an experiment tracker and an independently held-out evaluation.', 'Measure a real serving system; run accelerator/distributed training, checkpoint recovery and capacity tests on appropriate hardware.'],
  },
  {
    id: 'ai', title: 'Senior AI and LLM engineering',
    outcome: 'Build permission-aware retrieval and a tool executor whose authority, budget and evaluation do not depend on model obedience.',
    prerequisites: ['math', 'ml', 'llm', 'ai', 'ai-building-blocks'],
    courses: ['ai-production', 'ml-statistics', 'ml-production', 'deep-learning-practice', 'ai-systems', 'pytorch-training', 'transformer-engineering'],
    projects: ['project-authorized-rag', 'project-tool-executor', 'project-bm25project', 'project-indexproject', 'project-ragproject', 'project-planproject', 'project-batchproject', 'project-releaseproject', 'project-torchblock', 'project-torchtinylm', 'project-torchseqcls'],
    review: ['Evaluate retrieval separately from answer quality, citation support and end-to-end task success.', 'Demonstrate tenant filtering, exact-argument approval, replay handling and bounded tool execution.', 'Explain prompt injection limits, cache permissions, token accounting, regression evidence and failure recovery.'],
    fieldwork: ['Evaluate a real local or hosted LLM on versioned, representative and adversarial cases; report quality, latency and cost.', 'Operate retrieval/index updates and a controlled model or prompt rollout with observability, human review and rollback.'],
  },
] as const;
