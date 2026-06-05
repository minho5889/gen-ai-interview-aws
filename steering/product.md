# Steering: Product Context

> Loaded via the root `CLAUDE.md` (`@import`). Keep it short, true, and current — if something here
> is wrong, the agent will confidently build the wrong thing.

## What we're building

An agentic **Medical, Legal & Regulatory (MLR) review** system. It automates the first pass of
compliance review for pharma / medical-device marketing:

- Ingests a **Content** asset (the marketing draft) and a **Reference** pack (supporting evidence).
- Runs three independent reviews in parallel — **editorial**, **internal-evidence**,
  **external-evidence** (PubMed / openFDA).
- Produces a per-claim **verdict** (`Substantiated` | `Failed Validation` | `Needs Human Review`)
  with a resolvable **citation** for anything it substantiates.

It is **decision support**: it never publishes, and a human MLR reviewer makes the final call. The
agent's execution boundary is strictly **read-only**.

## Who it's for / who's building it

- **Domain users:** Regulatory Compliance Officers and clinical reviewers who today do this by hand.
- **The builder:** an engineer who knows AWS cold (Lambda, Step Functions, IAM, S3) but is newer to
  the agentic stack. In these docs and the spec, explain the agentic *why*; assume the AWS *what*.

## Definition of "done" for the spec

A spec section is done when a competent engineer could implement it **without asking a clarifying
question** and **without inventing an API**:

- Every requirement is testable (you can write the assertion before the code).
- Every external API named in the design actually exists in the pinned deps (see `tech.md`) —
  verified against source, not assumed.
- Failure modes, the security boundary, latency budget, and cost ceiling are stated, not implied.
- The design names *which Strands primitive* it uses and *why that one over the alternatives*.

## Non-goals

- Not optimizing for "most agents" — fewer, well-bounded agents win. The reviewer set is fixed at three.
- No UI. This is a backend, tools, and an orchestration graph.
- No code that calls an API we have not verified exists.
- The system never publishes or mutates source-of-truth data.
