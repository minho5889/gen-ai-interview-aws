# Tasks — World Cup 2026 Toronto Itinerary & Fan Guide Verifier

> Incremental, test-first plan. Each task cites the requirement IDs it satisfies. Coding tasks only.
> The ordering stands up a thin end-to-end skeleton early (Task 4), then deepens each reviewer.

## 0. Project scaffolding
- [ ] 0.1 Set up the `src/verifier/` package + `tests/`; verify deps in `.venv`: `pydantic`,
  `strands-agents`, `strands-agents-tools`, `mcp`, `opentelemetry-sdk`, `google-genai==1.75.0`
  (all confirmed present). Set `GOOGLE_API_KEY` env var (google-genai SDK default). _(infra)_
- [ ] 0.2 Define the travel data models from design §4 (`ItineraryActivity`, `Citation`, `Finding`,
  `ActivityReview`, `TripReport`) and write validation unit tests. _(Req 2, 5)_

## 1. Deterministic ingestion (no LLM yet)
- [ ] 1.1 Implement `process_pdf(file_path)` → page-numbered Markdown blocks. _(Req 1.1, 1.2, 1.4)_
- [ ] 1.2 Implement typed `IngestionError`; cover corrupt/non-PDF itinerary and booking confirmations with unit tests. _(Req 1.3)_
- [ ] 1.3 Implement `batch_content(blocks, max_tokens=4000)` → token-bounded batches + atomic activities
  with stable `batch_id`/`activity_id`; unit-test token boundaries and stable IDs. _(Req 2.1, 2.2, 2.3)_

## 2. Safety boundary (test before any live model call)
- [ ] 2.1 Implement `ReadOnlyGuard(HookProvider)` using `BeforeToolCallEvent` + `cancel_tool`
  (design §5). _(Req 4.1, 4.2)_
- [ ] 2.2 Unit-test the guard by constructing a synthetic `BeforeToolCallEvent` for each blocked verb;
  assert `cancel_tool` is set. _(Req 4.2)_
- [ ] 2.3 Set `GOOGLE_API_KEY` env var (google-genai SDK default); wire `GeminiModel` with
  `params={"temperature": 0.1, "max_output_tokens": 1500}` — NOT top-level kwargs. _(Req 4.3, 4.4)_

## 3. Evidence tools
- [ ] 3.1 Implement `query_google_drive(file_id)` (read-only) returning simulated flight details, hotel check-ins, and match tickets, backed by a local folder mock. _(Req 3.3, 5.2)_
- [ ] 3.2 Stand up the Web Search MCP server (local `stdio` for dev) exposing a typed `search_web` tool; connect via the `mcp_client` tool. _(Req 3.4, 5.2)_

## 4. Thin end-to-end skeleton (walking skeleton)
- [ ] 4.1 Build the three reviewer `Agent`s with Gemini models and `structured_output_model=Finding`; attach `ReadOnlyGuard`. _(Req 3.1, 3.2, 8.2)_
- [ ] 4.2 Assemble the `GraphBuilder` DAG: three parallel reviewer nodes → synthesis node; run one batch end-to-end with a mocked/stub model and assert all three nodes execute concurrently. _(Req 3.1)_
- [ ] 4.3 Implement the synthesis node + verdict rule as a pure function over `Finding`s; unit-test the rule table (stadium policy violation→Policy Conflict, booking conflict→Logistical Warning, otherwise→Verified). _(Req 5, 6.1)_

## 5. Reviewer depth
- [ ] 5.1 Editorial prompt: check spelling, tone, and trademark guidelines (commercial sponsor name "BMO Field" must be replaced with "Toronto Stadium" in public guides). _(Req 3.2)_
- [ ] 5.2 Logistics reviewer: verify dates/times against bookings; warn if flight landing time (YYZ) is too close to kickoff (Toronto Stadium), accounting for UP Express travel time. _(Req 3.3, 5.2, 5.5)_
- [ ] 5.3 Rules reviewer: check match schedules and Toronto Stadium policies (e.g. clear-bag rules, camera limits) using web search. _(Req 3.4, 5.2, 5.5)_
- [ ] 5.4 Invariant test: no `Verified` verdict anywhere lacks a Google Drive/Web URL citation. _(Req 5.5)_

## 6. Resilience & cost controls
- [ ] 6.1 Degraded-dimension handling: if a reviewer node errors/times out, mark that dimension `Needs Human Review` and continue; test by forcing one node to throw. _(Req 3.5)_
- [ ] 6.2 Wrap Gemini calls with exponential backoff + jitter on 429; cap retries then degrade. _(Req 8.4)_
- [ ] 6.3 Enforce per-batch `max_tokens` and an agent-loop token budget; test that an over-budget batch is truncated. _(Req 8.3)_

## 7. Report & synthesis output
- [ ] 7.1 Emit `TripReport` with `Policy Conflict` and `Logistical Warning` activities sorted first and a run summary. _(Req 6.1, 6.2, 6.3)_

## 8. Observability
- [ ] 8.1 Initialize `StrandsTelemetry().setup_console_exporter()`; attach `activity_id`/`batch_id` via `trace_attributes`. _(Req 7.1, 7.2)_
- [ ] 8.2 Log a discrete statement in the `ReadOnlyGuard` denial path (tool name + offending args + activity/batch context); test it fires. _(Req 7.3)_

## 9. Evaluation & performance gate
- [ ] 9.1 Build a golden set of 5 travel itinerary scenarios (e.g., flight arrives late, clear bag policy violation, incorrect game date) and an LLM-as-judge eval harness. _(Req 5)_
- [ ] 9.2 Latency check: assert completed report for a 3-day itinerary takes less than 60 seconds. _(Req 8.1)_

> **Implementation order rationale:** safety (Task 2) and deterministic tools (Task 1) land *before* any live model call, so the dangerous surface is tested with zero token spend. The walking skeleton (Task 4) proves the parallel topology early; reviewer depth and resilience layer on after the shape is verified.
