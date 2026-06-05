# Design — World Cup 2026 Toronto Itinerary & Fan Guide Verifier

> Verified against `strands_agents==1.42.0` / `strands_agents_tools==0.8.0` in `.venv`. Every class,
> hook event, and tool named below exists in the pinned deps. See `steering/tech.md`.

## 1. Overview

A **Strands `Graph`** (deterministic DAG) ingests the draft travel itinerary and bookings document, segments the content into individual activities, fans each activity out to three independent reviewer agents in parallel, joins their findings, and synthesizes a single consolidated trip safety report. A **read-only `HookProvider`** forms the safety boundary; **OpenTelemetry Console Exporter** provides stdout trace logs for debugging.

### Why `GraphBuilder`, not "agents-as-tools" (design decision, satisfies Req 3)

We use a **`Graph`** to enforce that all three review dimensions (editorial guidelines, private logistics, and public stadium policies) are executed concurrently and independently. Encoding this as structure ensures that if one reviewer node fails, we can recover gracefully and report warnings for that dimension, satisfying Requirement 3.5 without crashing the entire trip verification run.

---

## 2. Architecture

```mermaid
graph TD
    subgraph Ingestion (deterministic tools, not agents)
        Draft[Draft Itinerary PDF] --> OCR[process_pdf]
        Bookings[Bookings PDF] --> OCR
        OCR --> Seg[batch_content → ItineraryActivity list]
    end

    Seg --> Fan{{Graph: per-batch fan-out}}

    subgraph Parallel reviewer nodes (Strands Graph)
        Fan --> Edit[Editorial Agent<br/>gemini-2.5-flash]
        Fan --> Logistics[Logistics Agent<br/>tools: query_google_drive]
        Fan --> Rules[Rules & Schedule Agent<br/>tools: mcp_client → Web Search]
    end

    Edit --> Join[Join / Synthesis node]
    Logistics --> Join
    Rules --> Join
    Join --> Report[Final Trip Safety Report]

    Logistics -. read-only simulated drive + ReadOnlyGuard hook .-> GDrive[(Google Drive Booking confirmations)]
    Rules -. read-only .-> MCP[(Web Search MCP: Match schedule & BMO Field guidelines)]
    Join -. OTEL spans .-> Obs[(Console stdout trace logs)]
```

---

## 3. Components & interfaces

### 3.1 Deterministic tools (plain `@tool` functions — no LLM where logic is deterministic)

```python
@tool
def process_pdf(file_path: str) -> dict:
    """OCR an itinerary or bookings PDF to structured Markdown blocks with page numbers.

    Returns: {"blocks": [{"page": int, "markdown": str, "kind": "text|table|figure"}], "source": str}
    Raises a typed IngestionError (Req 1.3) on unreadable/encrypted/non-PDF input.
    """

@tool
def batch_content(blocks: list[dict], max_tokens: int = 4000) -> list["Batch"]:
    """Segment itinerary blocks into token-bounded batches; extract atomic activities (Req 2)."""

@tool
def query_google_drive(file_id: str) -> dict:
    """Read-only fetch of a travel booking reservation (flight, hotel, match ticket) from Google Drive.
    
    Returns content + the citable key. For local testing, this reads from a local directory mock 
    simulating Google Drive folder records.
    """
```

### 3.2 Reviewer agents (Graph nodes)

Each node is a `strands.Agent` wrapped as a `GraphBuilder` node. We use the Gemini provider (Req 8.2):

| Node | Model tier | Tools | System prompt focus |
|---|---|---|---|
| **Editorial** | `gemini-2.5-flash` | none | grammar, exciting travel tone, and FIFA trademark guidelines (Toronto Stadium vs BMO Field) |
| **Logistics** | `gemini-2.5-flash` | `query_google_drive` | check dates/times against flights, hotels, and tickets; warn on tight connections |
| **Rules & Schedule** | `gemini-2.5-flash` | `mcp_client` → Web Search | check match schedules, clear-bag policies, and transit routes in Toronto |

```python
from strands import Agent
from strands.models import GeminiModel
from strands.multiagent import GraphBuilder

# GeminiModel verified against strands_agents==1.42.0 / google-genai==1.75.0.
# - model_id and params are GeminiConfig keyword args (not top-level constructor params).
# - temperature/max_output_tokens go INSIDE params={} — they map to Google's GenerationConfig.
# - API key: set GOOGLE_API_KEY env var (google-genai SDK default); or pass explicitly via
#   client_args={"api_key": os.environ["GEMINI_API_KEY"]} if you prefer that name.
gemini_flash = GeminiModel(
    model_id="gemini-2.5-flash",
    params={"temperature": 0.1, "max_output_tokens": 1500},
)

editorial      = Agent(model=gemini_flash, system_prompt=EDITORIAL_PROMPT,
                       hooks=[ReadOnlyGuard()])
logistics      = Agent(model=gemini_flash, system_prompt=LOGISTICS_PROMPT,
                       tools=[query_google_drive], hooks=[ReadOnlyGuard()])
rules_schedule = Agent(model=gemini_flash, system_prompt=RULES_PROMPT,
                       tools=[mcp_web_search], hooks=[ReadOnlyGuard()])

b = GraphBuilder()
b.add_node(editorial,      "editorial")
b.add_node(logistics,      "logistics")
b.add_node(rules_schedule, "rules_schedule")
b.add_node(synthesis,      "synthesis")
b.add_edge("editorial",      "synthesis")
b.add_edge("logistics",      "synthesis")
b.add_edge("rules_schedule", "synthesis")
graph = b.build()
```

### 3.3 External evidence over MCP
The `Rules & Schedule` agent utilizes standard web search tools to pull live schedules and official BMO Field guidelines. This ensures that match changes or bag policies are factual and backed by live URL citations.

---

## 4. Data models

```python
from typing import Literal, Optional
from pydantic import BaseModel, HttpUrl

class ItineraryActivity(BaseModel):
    activity_id: str
    batch_id: str
    date: str
    time: str
    location: str
    description: str
    source_page: int

class Citation(BaseModel):
    kind: Literal["google_drive", "web"]
    locator: str          # gdrive://bookings/flight_confirm.pdf#page=1  |  URL link
    url: Optional[HttpUrl] # URL where one exists (Req 5.2)

class Finding(BaseModel):
    activity_id: str
    dimension: Literal["editorial", "logistics", "rules_schedule"]
    verdict: Literal["Verified", "Logistical Warning", "Policy Conflict", "Needs Human Review"]
    rationale: str
    citations: list[Citation] = []

class ActivityReview(BaseModel):           # produced by synthesis, one per activity
    activity: ItineraryActivity
    final_verdict: Literal["Verified", "Logistical Warning", "Policy Conflict", "Needs Human Review"]
    findings: list[Finding]

class TripReport(BaseModel):
    reviews: list[ActivityReview]       # Policy Conflict & Logistical Warning sorted first (Req 6.2)
    counts: dict[str, int]
    degraded_dimensions: list[str]      # reviewers that errored/timed out (Req 3.5)
    total_tokens: int
```

**Synthesis verdict rule (Req 5):** 
- `Policy Conflict` if the Rules reviewer flags a stadium rule violation.
- `Logistical Warning` if the Logistics reviewer flags a booking conflict (e.g. flight arrival time overlaps with game time) or missing ticket.
- `Needs Human Review` if any reviewer errored or was unable to resolve a warning.
- Otherwise, `Verified` only if the Logistics agent confirms a valid booking exists and the Rules agent confirms BMO Field/match-day details.

---

## 5. Safety boundary (Req 4)

We utilize the local application guard for hands-on validation:

```python
from strands.hooks import HookProvider, HookRegistry
from strands.hooks.events import BeforeToolCallEvent

class ReadOnlyGuard(HookProvider):
    BLOCKED = ("write", "delete", "update", "put_", "create", "drop", "remove", "cancel")
    def register_hooks(self, registry: HookRegistry) -> None:
        registry.add_callback(BeforeToolCallEvent, self._enforce)
    def _enforce(self, event: BeforeToolCallEvent) -> None:
        name = event.tool_use["name"].lower()
        if any(v in name for v in self.BLOCKED):
            event.cancel_tool = f"DENIED: '{name}' is a mutating operation; itinerary review is read-only."
```

---

## 6. Observability (Req 7)

We setup console telemetry:
```python
from strands.telemetry import StrandsTelemetry
StrandsTelemetry().setup_console_exporter()
```
Strands auto-emits stdout logs with trace details. The `ReadOnlyGuard` denial path prints structured log statements containing `activity_id` and `batch_id` to trace safety violations.

---

## 7. Error handling

| Failure | Detection | Behavior | Req |
|---|---|---|---|
| Unreadable PDF | `process_pdf` raises `IngestionError` | abort before any review; typed error names the file | 1.3 |
| Zero activities after segmentation | `batch_content` returns empty | terminate "no reviewable itinerary activities" | 2.3 |
| One reviewer errors/timeouts | Graph node failure | continue others; mark that dimension `Needs Human Review` | 3.5 |
| Gemini 429 throttling | model call error | exp. backoff + jitter, capped; then degrade dimension | 8.4 |
| Mutating tool attempted | `ReadOnlyGuard` | `cancel_tool` + log output; run continues | 4.2, 7.3 |
| `Verified` w/o citation | synthesis invariant | downgrade to `Needs Human Review` | 5.5 |

---

## 8. Testing strategy

- **Unit:** 
  - `process_pdf` on good/corrupt PDFs.
  - `batch_content` activity parsing and stable ID generation.
  - Synthesis rules: testing multiple combinations of `Logistical Warning` and `Policy Conflict` inputs.
- **Safety:** Assert `ReadOnlyGuard._enforce` intercepts block-listed tool calls.
- **Integration:** Running the Graph with stubbed Gemini models and verifying the parallel execution of Editorial, Logistics, and Rules & Schedule nodes.
- **Mock Google Drive:** Setup test fixtures (mock PDF/JSON files) representing flight details (YYZ landing times), hotel check-ins, and match tickets for Toronto Stadium (BMO Field).
