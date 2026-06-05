# Requirements — World Cup 2026 Toronto Itinerary & Fan Guide Verifier

> See `steering/` for the spec methodology (EARS) and the verified Strands/Gemini API surface
> this spec is allowed to reference.

## Introduction

Attending the FIFA World Cup 2026 in Toronto (hosted at Toronto Stadium / BMO Field) is a massive logistical undertaking. Fans need to coordinate flights into Pearson (YYZ) or Billy Bishop (YTZ) airports, schedule transit via the UP Express and GO Train to Exhibition Station, track their match ticket dates, and follow strict stadium rules (like clear-bag policies and cashless entry).

This system automates the **verification** of travel itineraries and fan guides: it ingests a **Draft Itinerary** and a **Bookings Folder** (flights, hotels, match tickets), runs three independent reviews in parallel — editorial, logistics, and stadium rules — and produces a consolidated trip safety report with citations. It is a **decision-support** tool: it helps fans spot logistical traps before they travel.

### Glossary
- **Activity** — an atomic event in the itinerary draft (e.g., "Transit to Toronto Stadium for Canada vs Match 3").
- **Booking** — a verified reservation record (flight, hotel, or match ticket) stored in Google Drive.
- **Verdict** — one of `Verified` | `Logistical Warning` | `Policy Conflict` | `Needs Human Review`, per activity.
- **Toronto Stadium** — the official tournament name for BMO Field during the World Cup 2026.

---

## Requirement 1 — Document ingestion & multimodal OCR

**User story:** As a traveler planning a group trip, I want my draft itinerary and my bookings folder converted to structured Markdown text, so that downstream review operates on accurate timings and flight details.

**Acceptance criteria:**
1. WHEN an Itinerary draft PDF and a Bookings PDF (containing ticket receipts) are submitted, THE SYSTEM SHALL convert each to Markdown, preserving times, dates, and flight/seat codes.
2. WHERE a page contains a transit map or ticket barcode context, THE SYSTEM SHALL emit alt-text or extracted metadata describing it inline.
3. IF a source file is not readable or is corrupt, THEN THE SYSTEM SHALL fail that ingestion with a typed error naming the file and SHALL NOT start any review.
4. THE SYSTEM SHALL record, for each extracted block, its source page number so that later citations can point to a page.

## Requirement 2 — Activity segmentation & review batching

**User story:** As an AI Systems Operator, I want the itinerary segmented into individual activities and batched under a token ceiling, so that no single model call exceeds context limits and each event is evaluated independently.

**Acceptance criteria:**
1. THE SYSTEM SHALL segment the Itinerary Markdown into activity chunks that each stay under a configurable token ceiling (default 4,000 input tokens).
2. THE SYSTEM SHALL assign every batch a stable `batch_id` and every activity a stable `activity_id` so findings can be correlated back to source text.
3. IF segmentation produces zero activities, THEN THE SYSTEM SHALL terminate with a "no reviewable itinerary activities" result rather than invoking any reviewer.

## Requirement 3 — Parallel, independent reviews

**User story:** As a traveler, I want spelling/layout checks, booking alignments, and stadium rule checks to run concurrently, so that the verification process is fast and no reviewer biases another.

**Acceptance criteria:**
1. WHEN a batch is ready, THE SYSTEM SHALL dispatch it to three reviewers — **Editorial**, **Logistics**, and **Rules & Schedule** — that execute concurrently.
2. THE Editorial reviewer SHALL check grammar, spelling, tone (exciting/helpful), and official FIFA/World Cup naming guidelines (e.g., using "Toronto Stadium" instead of commercial sponsor names for public guides), returning findings without consulting bookings or web stores.
3. THE Logistics reviewer SHALL attempt to verify each activity against the travel confirmations stored in the Google Drive bookings folder, flagging flight connection overlaps, check-in errors, or tight travel buffers (e.g., landing at YYZ and proposing to get to BMO Field in under 60 minutes).
4. THE Rules & Schedule reviewer SHALL verify each activity against public match schedules and BMO Field/Toronto Stadium regulations (such as bag size limits and camera rules) using Web Search MCP tools, returning stadium guidelines and URLs.
5. IF any one reviewer fails (error or timeout), THEN THE SYSTEM SHALL continue with the remaining reviewers and SHALL mark the affected dimension `Needs Human Review` rather than aborting the run.

## Requirement 4 — Read-only execution boundary

**User story:** As a traveler, I want a hard guarantee that the agent cannot modify my travel documents, bookings, or files, so that a misbehaving model cannot delete my ticket reservations.

**Acceptance criteria:**
1. THE SYSTEM SHALL deny any tool invocation whose operation is a write, update, delete, or create (e.g. attempting to cancel a flight booking).
2. IF a reviewer attempts a write operation, THEN THE SYSTEM SHALL cancel that tool call, return a structured denial to the model, and emit an audit event — and SHALL NOT crash the run.
3. WHERE external APIs or mock filesystems are accessed, THE SYSTEM SHALL ensure they are opened in read-only mode.
4. WHILE processing any content, THE SYSTEM SHALL configure the Gemini model safety settings to handle prompt-injection and inappropriate content.

## Requirement 5 — Citations & verdicts

**User story:** As a traveler, I want every warning backed by a clickable citation, so that I can verify the error directly with my airline or the stadium website.

**Acceptance criteria:**
1. THE SYSTEM SHALL assign each activity exactly one final verdict: `Verified`, `Logistical Warning`, `Policy Conflict`, or `Needs Human Review`.
2. WHERE an activity is `Verified` or has a warning, THE SYSTEM SHALL attach at least one citation resolving to a concrete location: a Google Drive file ID + page (logistics) or a verified website URL (rules & schedule).
3. IF an activity violates a stadium policy (e.g., "bringing a 30L hiking pack to the match"), THEN THE SYSTEM SHALL mark it `Policy Conflict` and record a rationale referencing the BMO Field bag policy URL.
4. IF an activity has a logistical conflict (e.g., "checking out of hotel on June 25th but match ticket is June 26th"), THEN THE SYSTEM SHALL mark it `Logistical Warning` and reference the specific booking file in Google Drive.
5. THE SYSTEM SHALL NOT emit a `Verified` verdict for match attendance without verifying the ticket booking exists in Google Drive and matches the official schedule.

## Requirement 6 — Synthesis & consolidated report

**User story:** As a traveler, I want one consolidated itinerary report, so that I can review all trip warnings at a glance before departure.

**Acceptance criteria:**
1. WHEN all reviewers for all batches have returned (or been marked `Needs Human Review`), THE SYSTEM SHALL synthesize a single report aggregating per-activity verdicts, findings, and citations.
2. THE report SHALL surface every `Policy Conflict` and `Logistical Warning` activity before any `Verified` activity.
3. THE report SHALL include a run summary: counts per verdict, reviewers that degraded, and total token cost.

## Requirement 7 — Observability & auditability

**User story:** As an AI Systems Operator, I want every model call, tool call, and policy decision traced, so that I can debug why an itinerary item was verified or flagged.

**Acceptance criteria:**
1. THE SYSTEM SHALL emit OpenTelemetry traces for the orchestrator loop, each model call, and each tool call.
2. THE SYSTEM SHALL record, per run, token usage and latency, exported to the terminal stdout console using the OpenTelemetry console exporter.
3. WHEN the read-only guard cancels a tool call, THE SYSTEM SHALL emit a discrete audit log capturing the tool name, the offending arguments, and the itinerary context.

## Requirement 8 — Performance & cost (non-functional)

**User story:** As a traveler, I want my itinerary checked quickly, so that I can iterate on my travel plans without long wait times.

**Acceptance criteria:**
1. THE SYSTEM SHALL return a completed report for a 3-day itinerary draft within **60 seconds p95**.
2. THE SYSTEM SHALL route editorial review to a fast model tier (`gemini-2.5-flash`) and logistics/rule verification to the configured Gemini model (model tiering).
3. THE SYSTEM SHALL cap each reviewer's per-batch generation via `max_tokens` and bound the agent loop so a single batch cannot exceed a configurable token budget.
4. IF a Gemini API call returns a throttling error (HTTP 429), THEN THE SYSTEM SHALL retry with exponential backoff and jitter up to a configured maximum before degrading that dimension.
