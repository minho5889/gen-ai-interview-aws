# Tasks — Medical Content Review (MLR) Workflow

> Incremental, test-first plan. Each task cites the requirement IDs it satisfies. Coding tasks only.
> The ordering stands up a thin end-to-end skeleton early (Task 4), then deepens each reviewer.

## 0. Project scaffolding
- [ ] 0.1 Set up the `src/mlr/` package (already scaffolded) + `tests/`; add `pydantic`,
  `strands-agents`, `strands-agents-tools`, `mcp`, `opentelemetry-sdk` to deps (most already in
  `.venv`). _(infra)_
- [ ] 0.2 Define the data models from design §4 (`Claim`, `Citation`, `Finding`, `ClaimReview`,
  `RunReport`) and write their construction/validation unit tests first. _(Req 2, 5)_

## 1. Deterministic ingestion (no LLM yet)
- [ ] 1.1 Implement `process_pdf(file_path)` → page-numbered Markdown blocks with figure alt-text.
  _(Req 1.1, 1.2, 1.4)_
- [ ] 1.2 Implement typed `IngestionError`; cover encrypted/corrupt/non-PDF fixtures with unit tests
  that assert no review starts. _(Req 1.3)_
- [ ] 1.3 Implement `batch_content(blocks, max_tokens=4000)` → token-bounded batches + atomic claims
  with stable `batch_id`/`claim_id`; unit-test the token ceiling, id stability, and empty-input
  termination. _(Req 2.1, 2.2, 2.3)_

## 2. Safety boundary (test before any live model call)
- [ ] 2.1 Implement `ReadOnlyGuard(HookProvider)` using `BeforeToolCallEvent` + `cancel_tool`
  (design §5). _(Req 4.1, 4.2)_
- [ ] 2.2 Unit-test the guard by constructing a synthetic `BeforeToolCallEvent` for each blocked verb;
  assert `cancel_tool` is set and the run is not killed. _(Req 4.2)_
- [ ] 2.3 Author the read-only IAM policy (`s3:GetObject` only) for the tool compute role and the
  Bedrock Guardrail config; wire `guardrail_id`/`guardrail_version` into `BedrockModel`.
  _(Req 4.3, 4.4)_

## 3. Evidence tools
- [ ] 3.1 Implement `query_s3_documents(bucket, key)` (read-only) returning content + citable
  `s3://…#page=` locator. _(Req 3.3, 5.2)_
- [ ] 3.2 Stand up the PubMed/openFDA MCP server (local `stdio` for dev) exposing typed
  `search_pubmed`/`lookup_openfda` tools; connect via the `mcp_client` tool. _(Req 3.4, 5.2)_

## 4. Thin end-to-end skeleton (walking skeleton)
- [ ] 4.1 Build the three reviewer `Agent`s with tiered models (Haiku editorial, Sonnet evidence) and
  `structured_output_model=Finding`; attach `ReadOnlyGuard`. _(Req 3.1, 3.2, 8.2)_
- [ ] 4.2 Assemble the `GraphBuilder` DAG: three parallel reviewer nodes → synthesis node; run one
  batch end-to-end with a mocked/stub model and assert all three nodes execute concurrently.
  _(Req 3.1)_
- [ ] 4.3 Implement the synthesis node + verdict rule as a pure function over `Finding`s; unit-test
  the rule table (contradiction→Failed, citation→Substantiated, else→Needs Human Review). _(Req 5,
  6.1)_

## 5. Reviewer depth
- [ ] 5.1 Editorial prompt + assertions for grammar/tone/FDA fair-balance findings. _(Req 3.2)_
- [ ] 5.2 Internal reviewer: substantiate against Reference pack + S3; require an S3+page citation on
  every `Substantiated`. _(Req 3.3, 5.2, 5.5)_
- [ ] 5.3 External reviewer: substantiate against PubMed/openFDA; require an ID+URL citation on every
  `Substantiated`. _(Req 3.4, 5.2, 5.5)_
- [ ] 5.4 Invariant test: no `Substantiated` verdict anywhere lacks a resolvable citation. _(Req 5.5)_

## 6. Resilience & cost controls
- [ ] 6.1 Degraded-dimension handling: if a reviewer node errors/times out, mark that dimension
  `Needs Human Review` and continue; test by forcing one node to throw. _(Req 3.5)_
- [ ] 6.2 Wrap Bedrock calls with exponential backoff + jitter on 429; cap retries then degrade.
  _(Req 8.4)_
- [ ] 6.3 Enforce per-batch `max_tokens` and an agent-loop token budget; test that an over-budget
  batch is truncated, not run away. _(Req 8.3)_

## 7. Report & synthesis output
- [ ] 7.1 Emit `RunReport` with `Failed Validation` claims sorted first and a run summary (counts,
  degraded dimensions, total tokens). _(Req 6.1, 6.2, 6.3)_

## 8. Observability
- [ ] 8.1 Initialize `StrandsTelemetry().setup_otlp_exporter()`; set `OTEL_*` env and attach
  `claim_id`/`batch_id` via `trace_attributes`. _(Req 7.1, 7.2)_
- [ ] 8.2 Emit a discrete audit span in the `ReadOnlyGuard` denial path (tool name + offending args
  + claim/batch context); test it fires. _(Req 7.3)_

## 9. Evaluation & performance gate
- [ ] 9.1 Build a golden set of claim→expected-verdict pairs and an LLM-as-judge eval harness (no
  "Strands Evals" library — verify any eval dependency before adding it). _(Req 5)_
- [ ] 9.2 p95 latency check on a 10-page asset; fail the gate if > 120s. _(Req 8.1)_

> **Implementation order rationale:** safety (Task 2) and deterministic tools (Task 1) land *before*
> any live model call, so the dangerous surface is tested with zero token spend. The walking skeleton
> (Task 4) proves the parallel topology early; reviewer depth and resilience layer on after the shape
> is verified.
