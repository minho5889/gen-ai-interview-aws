# Design — Medical Content Review (MLR) Workflow

> Verified against `strands_agents==1.42.0` / `strands_agents_tools==0.8.0` in `.venv`. Every class,
> hook event, and tool named below exists in the pinned deps or in AWS managed-service docs. See
> `steering/tech.md`.

## 1. Overview

A **Strands `Graph`** (deterministic DAG) ingests two PDFs, segments the content into batches, fans
each batch out to three independent reviewer agents in parallel, joins their findings, and synthesizes
a single per-claim report. A **read-only `HookProvider`** and **Bedrock Guardrails** form the safety
boundary; **OpenTelemetry via `StrandsTelemetry`** provides the audit trail. The system is
decision-support only — it produces verdicts and citations, never publishes.

### Why `GraphBuilder`, not "agents-as-tools" (design decision, satisfies Req 3)

The original spec modeled the reviewers as tools the orchestrator "calls in parallel." That makes
parallelism a *model decision* — non-deterministic and unauditable, and Req 3.1 demands the three
reviewers *always* run concurrently. A **`Graph`** encodes that as structure: three reviewer nodes
with no edges between them (so the runtime executes them in parallel) converging on a join node.
Determinism, traceable topology, and per-node retry come for free. Agents-as-tools is reserved for
*optional* specialists, which we don't have here.

## 2. Architecture

```mermaid
graph TD
    subgraph Ingestion (deterministic tools, not agents)
        Content[Content PDF] --> OCR[process_pdf]
        Ref[Reference PDF] --> OCR
        OCR --> Seg[batch_content → claims + batch_ids]
    end

    Seg --> Fan{{Graph: per-batch fan-out}}

    subgraph Parallel reviewer nodes (Strands Graph)
        Fan --> Edit[Editorial Agent<br/>cheap model tier]
        Fan --> Internal[Internal Evidence Agent<br/>tools: query_s3_documents, retrieve]
        Fan --> External[External Evidence Agent<br/>tools: mcp_client → PubMed/openFDA]
    end

    Edit --> Join[Join / Synthesis node]
    Internal --> Join
    External --> Join
    Join --> Report[Final MLR Report]

    Internal -. read-only IAM + ReadOnlyGuard hook .-> S3[(Private S3 evidence)]
    External -. read-only .-> MCP[(Lambda/Gateway MCP: PubMed, openFDA)]
    Join -. OTEL spans .-> Obs[(AgentCore Observability / CloudWatch)]
```

## 3. Components & interfaces

### 3.1 Deterministic tools (plain `@tool` functions — no LLM where logic is deterministic)

```python
@tool
def process_pdf(file_path: str) -> dict:
    """OCR a PDF to structured Markdown blocks with page numbers and figure alt-text.

    Returns: {"blocks": [{"page": int, "markdown": str, "kind": "text|table|figure"}], "source": str}
    Raises a typed IngestionError (Req 1.3) on unreadable/encrypted/non-PDF input.
    """

@tool
def batch_content(blocks: list[dict], max_tokens: int = 4000) -> list["Batch"]:
    """Segment content blocks into token-bounded batches; extract atomic claims (Req 2)."""

@tool
def query_s3_documents(bucket: str, key: str) -> dict:
    """Read-only fetch of an internal evidence object from S3. Returns content + the citable key.
    Read-only by design: the IAM role grants s3:GetObject only (Req 4.3)."""
```

> **PE note:** OCR and segmentation are *deterministic* — make them tools, not agents. Spending a
> reasoning model on "split this text into 4k-token chunks" burns tokens and adds non-determinism.
> Reserve the LLM for judgment (substantiation), not arithmetic.

### 3.2 Reviewer agents (Graph nodes)

Each node is a `strands.Agent` wrapped as a `GraphBuilder` node. Models are tiered (Req 8.2):

| Node | Model tier | Tools | System prompt focus |
|---|---|---|---|
| **Editorial** | Haiku (cheap) | none | grammar, tone, FDA fair-balance/formatting |
| **Internal Evidence** | Sonnet | `query_s3_documents`, `retrieve` (Bedrock KB) | substantiate vs. private evidence; emit S3+page citation |
| **External Evidence** | Sonnet | `mcp_client` → PubMed + openFDA | substantiate vs. public lit; emit ID+URL citation |

```python
from strands import Agent
from strands.models import BedrockModel
from strands.multiagent import GraphBuilder

sonnet = BedrockModel(model_id="global.anthropic.claude-sonnet-4-6", temperature=0.1,
                      max_tokens=1500, guardrail_id=GUARDRAIL_ID, guardrail_version="DRAFT")
haiku  = BedrockModel(model_id="global.anthropic.claude-haiku-4-5", temperature=0.0, max_tokens=800)

editorial = Agent(model=haiku,  system_prompt=EDITORIAL_PROMPT, hooks=[ReadOnlyGuard()])
internal  = Agent(model=sonnet, system_prompt=INTERNAL_PROMPT, tools=[query_s3_documents, retrieve],
                  hooks=[ReadOnlyGuard()])
external  = Agent(model=sonnet, system_prompt=EXTERNAL_PROMPT, tools=[mcp_pubmed, mcp_openfda],
                  hooks=[ReadOnlyGuard()])

b = GraphBuilder()
b.add_node(editorial, "editorial")
b.add_node(internal,  "internal")
b.add_node(external,  "external")
b.add_node(synthesis, "synthesis")
# No edges among reviewers ⇒ they run in parallel; all converge on synthesis (Req 3.1, 6.1)
b.add_edge("editorial", "synthesis")
b.add_edge("internal",  "synthesis")
b.add_edge("external",  "synthesis")
graph = b.build()
```

> Verify `GraphBuilder`'s exact `add_node`/`add_edge`/entry-point signatures against
> `.venv/.../strands/multiagent/graph.py` for v1.42 — the shape is as above; confirm parameter names
> before coding.

### 3.3 External evidence over MCP

PubMed/openFDA are reached with the `mcp_client` tool from `strands_agents_tools`, pointed at an MCP
server. For this lab, that server can run as a local `stdio` process (mirroring `.mcp.json`);
in production it is a Lambda/Fargate-hosted HTTP MCP server, ideally fronted by **AgentCore Gateway**
(managed auth, turns the API into MCP tools). The agent never makes raw HTTP from free-text — it calls
typed MCP tools (`search_pubmed(query)`, `lookup_openfda(ndc)`).

## 4. Data models

```python
from typing import Literal, Optional
from pydantic import BaseModel, HttpUrl

class Claim(BaseModel):
    claim_id: str
    batch_id: str
    text: str
    source_page: int

class Citation(BaseModel):
    kind: Literal["internal_s3", "pubmed", "openfda"]
    locator: str          # s3://bucket/key#page=3  |  PMID:12345678  |  openFDA set id
    url: Optional[HttpUrl] # resolvable link where one exists (Req 5.2)

class Finding(BaseModel):
    claim_id: str
    dimension: Literal["editorial", "internal", "external"]
    verdict: Literal["Substantiated", "Failed Validation", "Needs Human Review"]
    rationale: str
    citations: list[Citation] = []

class ClaimReview(BaseModel):           # produced by synthesis, one per claim
    claim: Claim
    final_verdict: Literal["Substantiated", "Failed Validation", "Needs Human Review"]
    findings: list[Finding]

class RunReport(BaseModel):
    reviews: list[ClaimReview]          # Failed Validation sorted first (Req 6.2)
    counts: dict[str, int]
    degraded_dimensions: list[str]      # reviewers that errored/timed out (Req 3.5)
    total_tokens: int
```

**Synthesis verdict rule (Req 5):** `Failed Validation` if any reviewer found a contradiction;
else `Substantiated` only if an evidence reviewer attached a resolvable citation; else
`Needs Human Review`. A `Substantiated` verdict with no citation is a bug, asserted in tests.

> Use `Agent(structured_output_model=Finding)` so reviewers return validated `Finding` objects
> instead of free text you have to parse — this is built into Strands (Req 5, reliability).

## 5. Safety boundary (Req 4)

Two independent controls plus IAM (defense in depth):

```python
from strands.hooks import HookProvider, HookRegistry
from strands.hooks.events import BeforeToolCallEvent

class ReadOnlyGuard(HookProvider):
    BLOCKED = ("write", "delete", "update", "put_", "create", "drop", "remove")
    def register_hooks(self, registry: HookRegistry) -> None:
        registry.add_callback(BeforeToolCallEvent, self._enforce)
    def _enforce(self, event: BeforeToolCallEvent) -> None:
        name = event.tool_use["name"].lower()
        if any(v in name for v in self.BLOCKED):
            event.cancel_tool = f"DENIED: '{name}' is a write op; MLR review is read-only."
            # cancel_tool returns a clean tool-result to the model (Req 4.2) and is captured
            # as an audit span (Req 7.3). We do NOT raise — that would kill the whole run.
```

1. **Application guard:** `ReadOnlyGuard` on every agent (above).
2. **Model guard:** Bedrock Guardrails via `BedrockModel(guardrail_id=...)` — PII redaction +
   prompt-injection filtering (Req 4.4).
3. **Infra guard:** the tool compute's IAM role is read-only (`s3:GetObject`, no `PutObject`); even
   if both software guards failed, the blast radius is read-only (Req 4.3).

## 6. Observability (Req 7)

```python
from strands.telemetry import StrandsTelemetry
StrandsTelemetry().setup_otlp_exporter()   # OTEL_EXPORTER_OTLP_ENDPOINT → AgentCore Obs / CloudWatch
```

Strands auto-emits spans for the loop, model calls, and tool calls. We add a custom span in the
`ReadOnlyGuard` denial path and attach `claim_id`/`batch_id` via `trace_attributes` so audit queries
can pivot on a claim.

## 7. Error handling

| Failure | Detection | Behavior | Req |
|---|---|---|---|
| Unreadable PDF | `process_pdf` raises `IngestionError` | abort before any review; typed error names the file | 1.3 |
| Zero claims after segmentation | `batch_content` returns empty | terminate "no reviewable content" | 2.3 |
| One reviewer errors/timeouts | Graph node failure | continue others; mark that dimension `Needs Human Review` | 3.5 |
| Bedrock 429 throttling | model call error | exp. backoff + jitter, capped; then degrade dimension | 8.4 |
| Write tool attempted | `ReadOnlyGuard` | `cancel_tool` + audit span; run continues | 4.2, 7.3 |
| `Substantiated` w/o citation | synthesis invariant | downgrade to `Needs Human Review`; log a bug metric | 5.5 |

## 8. Testing strategy

- **Unit (deterministic, no LLM):** `process_pdf` on good/encrypted/non-PDF fixtures (Req 1);
  `batch_content` token-ceiling + claim-id stability + empty-input path (Req 2); synthesis verdict
  rule as a pure function over `Finding` lists (Req 5) — table-driven, no model calls.
- **Safety (no LLM):** call `ReadOnlyGuard._enforce` with a synthetic `BeforeToolCallEvent` for each
  blocked verb; assert `cancel_tool` is set and an audit span is emitted (Req 4, 7.3).
- **Integration (mocked model):** swap `BedrockModel` for `OllamaModel`/`LiteLLMModel` or a stub so
  the Graph topology, parallel fan-out, and degraded-dimension path run offline (Req 3.5).
- **Eval harness:** a golden set of claim→expected-verdict pairs scored by an independent
  LLM-as-judge. (There is no verified "Strands Evals" package — build this harness or use Bedrock
  model evaluation; do not name a library that doesn't exist.)
- **Invariant test:** assert no `Substantiated` verdict ever lacks a resolvable citation (Req 5.5).

## 9. Requirements traceability

| Requirement | Realized by |
|---|---|
| 1 Ingestion/OCR | `process_pdf` (§3.1), error table (§7) |
| 2 Batching | `batch_content` (§3.1), `Claim`/`Batch` models (§4) |
| 3 Parallel reviews | `GraphBuilder` topology (§2, §3.2), degraded-dimension handling (§7) |
| 4 Read-only boundary | `ReadOnlyGuard` + Guardrails + IAM (§5) |
| 5 Citations/verdicts | data models + synthesis rule (§4), invariant test (§8) |
| 6 Synthesis/report | synthesis node + `RunReport` (§3.2, §4) |
| 7 Observability | `StrandsTelemetry` + audit span (§6) |
| 8 Perf/cost | model tiering (§3.2), `max_tokens`, backoff (§7) |
