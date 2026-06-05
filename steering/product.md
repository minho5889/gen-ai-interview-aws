# Steering: Product Context

> Loaded via the root `CLAUDE.md` (`@import`). Keep it short, true, and current — if something here
> is wrong, the agent will confidently build the wrong thing.

## What we're building

An agentic **World Cup 2026 Toronto Itinerary & Fan Guide Verifier**. It automates verification of
travel plans for fans attending matches at Toronto Stadium (BMO Field):

- Ingests a **Draft Itinerary** (the trip plan) and a **Bookings** folder (flights, hotel, tickets).
- Runs three independent reviews in parallel — **editorial** (tone/naming guidelines), **logistics**
  (bookings alignment), and **rules & schedule** (live match schedules + stadium policies).
- Produces a per-activity **verdict** (`Verified` | `Logistical Warning` | `Policy Conflict` |
  `Needs Human Review`) with a resolvable **citation** for each finding.

It is **decision support**: it never modifies documents, and the traveler makes the final call. The
agent's execution boundary is strictly **read-only**.

## Who it's for / who's building it

- **Domain user:** A traveler (or group trip organizer) attending World Cup 2026 Toronto.
- **The builder:** An engineer new to the agentic stack but fluent in AWS and cloud infrastructure.
  Explain the agentic *why*; assume the cloud/Python *what*.

## Model provider

**`GeminiModel`** via the **Gemini API** (direct, not via Bedrock). Requires a `GOOGLE_API_KEY`.
This is the right choice for local development — no AWS account or IAM setup needed. Bedrock becomes
relevant when deploying on AWS for enterprise (different project context).

## Definition of "done" for the spec

A spec section is done when a competent engineer could implement it **without asking a clarifying
question** and **without inventing an API**:

- Every requirement is testable (you can write the assertion before the code).
- Every external API named in the design actually exists in pinned deps (see `tech.md`) —
  verified against source, not assumed.
- Failure modes, the security boundary, and latency budget are stated, not implied.
- The design names *which Strands primitive* it uses and *why that one over alternatives*.

## Non-goals

- No UI. This is a backend, tools, and an orchestration graph.
- No code that calls an API we have not verified exists.
- The system never modifies travel documents or bookings.
