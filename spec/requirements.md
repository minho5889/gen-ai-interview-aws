# Requirements — Medical Content Review (MLR) Workflow

> See `steering/` for the spec methodology (EARS) and the verified Strands/AgentCore API surface
> this spec is allowed to reference.

## Introduction

Pharmaceutical and medical-device marketing must pass **Medical, Legal, and Regulatory (MLR)**
review before publication: every claim in a piece of promotional content must be substantiated by
on-label evidence, carry the right disclaimers, and not contradict the science. Today this is a slow,
manual, multi-reviewer process.

This system automates the *first pass*: it ingests a **Content** asset (the marketing draft) and a
**Reference** pack (the supporting evidence), runs three independent reviews in parallel — editorial,
internal-evidence, and external-evidence — and produces a per-claim verdict with citations. It is a
**decision-support** tool: it never publishes, and a human MLR reviewer makes the final call. The
agent's execution boundary is strictly **read-only**.

### Glossary
- **Claim** — an atomic, checkable assertion in the content (e.g., "reduces A1C by 1.2%").
- **Substantiation** — an evidence item (internal study or external publication) that supports a claim.
- **Verdict** — one of `Substantiated` | `Failed Validation` | `Needs Human Review`, per claim.
- **Content / Reference PDF** — the marketing draft / the supporting evidence pack.

---

## Requirement 1 — Document ingestion & multimodal OCR

**User story:** As a Regulatory Compliance Officer, I want the Content and Reference PDFs converted
to faithful, structured Markdown, so that downstream review operates on text that preserves tables,
lists, and figure context rather than losing it.

**Acceptance criteria:**
1. WHEN a Content PDF and a Reference PDF are submitted, THE SYSTEM SHALL convert each to Markdown,
   preserving heading hierarchy, tables, and ordered/unordered lists.
2. WHERE a page contains a figure or chart, THE SYSTEM SHALL emit alt-text describing it inline.
3. IF a source file is not a readable PDF (corrupt, password-protected, or non-PDF), THEN THE SYSTEM
   SHALL fail that ingestion with a typed error naming the file and SHALL NOT start any review.
4. THE SYSTEM SHALL record, for each extracted block, its source page number so that later citations
   can point to a page.

## Requirement 2 — Claim segmentation & review batching

**User story:** As an AI Systems Operator, I want the content segmented into bounded review batches,
so that no single model call exceeds the context window and each claim is independently traceable.

**Acceptance criteria:**
1. THE SYSTEM SHALL segment the Content Markdown into batches that each stay under a configurable
   token ceiling (default 4,000 input tokens).
2. THE SYSTEM SHALL assign every batch a stable `batch_id` and every extracted claim a stable
   `claim_id` so verdicts can be correlated back to source text.
3. IF segmentation produces zero claims, THEN THE SYSTEM SHALL terminate with a "no reviewable
   content" result rather than invoking any reviewer.

## Requirement 3 — Parallel, independent reviews

**User story:** As a Compliance Officer, I want editorial, internal-evidence, and external-evidence
checks to run concurrently and independently, so that throughput is high and no reviewer biases
another.

**Acceptance criteria:**
1. WHEN a batch is ready, THE SYSTEM SHALL dispatch it to three reviewers — **Editorial**,
   **Internal Evidence**, and **External Evidence** — that execute concurrently.
2. THE Editorial reviewer SHALL check grammar, spelling, tone, and FDA fair-balance/formatting, and
   SHALL return findings without consulting evidence stores.
3. THE Internal Evidence reviewer SHALL attempt to substantiate each claim against the private
   Reference pack and the internal S3 evidence store, returning a citation (S3 object + page) per
   substantiated claim.
4. THE External Evidence reviewer SHALL attempt to substantiate each claim against public sources
   (PubMed, openFDA) via MCP tools, returning a citation (article/registry ID + URL) per
   substantiated claim.
5. IF any one reviewer fails (error or timeout), THEN THE SYSTEM SHALL continue with the remaining
   reviewers and SHALL mark the affected dimension `Needs Human Review` rather than aborting the run.

## Requirement 4 — Read-only execution boundary

**User story:** As an AI Systems Operator, I want a hard guarantee that no agent can mutate data,
so that a prompt-injected or misbehaving model cannot write to, or delete from, our systems.

**Acceptance criteria:**
1. THE SYSTEM SHALL deny any tool invocation whose operation is a write, update, delete, or create.
2. IF a reviewer attempts a denied operation, THEN THE SYSTEM SHALL cancel that tool call, return a
   structured denial to the model, and emit an audit event — and SHALL NOT crash the run.
3. THE compute identity (IAM role) under which evidence tools run SHALL grant read-only access only;
   the application-level guard is defense in depth, not the sole control.
4. WHILE processing any content, THE SYSTEM SHALL pass model input/output through Bedrock Guardrails
   for PII redaction and prompt-injection filtering.

## Requirement 5 — Citations & verdicts

**User story:** As a Regulatory Compliance Officer, I want every claim's verdict backed by a
clickable citation, so that I can verify substantiation in one click instead of re-researching.

**Acceptance criteria:**
1. THE SYSTEM SHALL assign each claim exactly one verdict: `Substantiated`, `Failed Validation`, or
   `Needs Human Review`.
2. WHERE a claim is `Substantiated`, THE SYSTEM SHALL attach at least one citation resolving to a
   concrete location: an S3 object key + page (internal) or an article/registry ID + URL (external).
3. IF a claim contradicts internal evidence or a public study, THEN THE SYSTEM SHALL mark it
   `Failed Validation` and SHALL record a rationale referencing the contradicting source.
4. IF no reviewer can confirm or refute a claim, THEN THE SYSTEM SHALL mark it `Needs Human Review`.
5. THE SYSTEM SHALL NOT emit a `Substantiated` verdict without a resolvable citation.

## Requirement 6 — Synthesis & final report

**User story:** As a Compliance Officer, I want one consolidated report, so that I review a single
prioritized artifact instead of three reviewer outputs.

**Acceptance criteria:**
1. WHEN all reviewers for all batches have returned (or been marked `Needs Human Review`), THE
   SYSTEM SHALL synthesize a single report aggregating per-claim verdicts, findings, and citations.
2. THE report SHALL surface every `Failed Validation` claim before any `Substantiated` claim.
3. THE report SHALL include a run summary: counts per verdict, reviewers that degraded, and total
   token cost.

## Requirement 7 — Observability & auditability

**User story:** As an AI Systems Operator, I want every model call, tool call, and policy decision
traced, so that an MLR run is auditable after the fact.

**Acceptance criteria:**
1. THE SYSTEM SHALL emit OpenTelemetry traces for the orchestrator loop, each model call, and each
   tool call.
2. THE SYSTEM SHALL record, per run, token usage and latency, exported over OTLP.
3. WHEN the read-only guard cancels a tool call, THE SYSTEM SHALL emit a discrete audit span
   capturing the tool name, the offending arguments, and the claim/batch context.

## Requirement 8 — Performance & cost (non-functional)

**User story:** As an AI Systems Operator, I want bounded latency and cost, so that the system is
viable at the volume of a real MLR queue.

**Acceptance criteria:**
1. THE SYSTEM SHALL return a completed report for a 10-page Content asset within **120 seconds p95**.
2. THE SYSTEM SHALL route editorial review (a cheap, no-evidence task) to a smaller/cheaper model
   tier than evidence reasoning (model tiering).
3. THE SYSTEM SHALL cap each reviewer's per-batch generation via `max_tokens` and bound the agent
   loop so a single batch cannot exceed a configurable token budget.
4. IF a Bedrock call returns a throttling error (HTTP 429), THEN THE SYSTEM SHALL retry with
   exponential backoff and jitter up to a configured maximum before degrading that dimension.
