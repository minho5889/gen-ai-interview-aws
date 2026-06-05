# Steering: Repo Structure & Spec Workflow

## 1. Repository layout

```
gen-ai-interview/                # (World Cup 2026 Toronto Verifier)
├── CLAUDE.md                    # always-on context for Claude Code; @imports steering/*
├── steering/                    # product.md, tech.md, structure.md
├── spec/                        # requirements.md → design.md → tasks.md (source of truth)
├── src/verifier/                # implementation
├── tests/                       # tests
├── .mcp.json                    # local MCP servers (fetch, filesystem)
├── start-mcp.sh                 # manual MCP launcher (debugging)
└── archive/                     # parked specs + interview-prep docs — NOT part of this project
```

## 2. The spec workflow — three phases, with gates

The discipline: **do not write implementation code until the spec is agreed.** Each phase produces
one file and has an explicit approval gate before the next.

```
   requirements.md            design.md                tasks.md
   (the WHAT + WHY)   ─approve→ (the HOW)      ─approve→ (the STEPS)   ─approve→ implement
```

1. **`spec/requirements.md`** — user stories + **EARS** acceptance criteria. No solution detail.
2. **`spec/design.md`** — architecture, components/interfaces, data models, error handling, testing.
   Every design decision traces back to a requirement ID. Names only verified APIs (see `tech.md`).
3. **`spec/tasks.md`** — a numbered, checkbox, *incremental* implementation plan. Coding tasks only.
   Each task cites the requirement IDs it satisfies.

> The value of a spec is the *forcing function*, not the document. Writing EARS forces you to find
> the ambiguity ("what does 'fast' mean — 2s p95?"). Writing the data model forces you to find the
> missing field. If a phase feels like paperwork, you're writing prose instead of decisions — stop
> and make a decision.

## 3. EARS — the requirement syntax (use it for every acceptance criterion)

EARS = Easy Approach to Requirements Syntax. Five templates; combine as needed:

| Pattern | Template | Example |
|---|---|---|
| Ubiquitous | THE SYSTEM SHALL `<behavior>` | THE SYSTEM SHALL store every review verdict with a citation. |
| Event-driven | **WHEN** `<trigger>`, THE SYSTEM SHALL `<behavior>` | WHEN a Content PDF is submitted, THE SYSTEM SHALL OCR it to Markdown within 60s. |
| State-driven | **WHILE** `<state>`, THE SYSTEM SHALL `<behavior>` | WHILE a guardrail block is active, THE SYSTEM SHALL reject all write tools. |
| Optional | **WHERE** `<feature is present>`, THE SYSTEM SHALL `<behavior>` | WHERE OpenSearch is configured, THE SYSTEM SHALL use it for evidence retrieval. |
| Unwanted | **IF** `<unwanted trigger>`, **THEN** THE SYSTEM SHALL `<behavior>` | IF a claim contradicts internal evidence, THEN THE SYSTEM SHALL mark it "Failed Validation". |

Rules:
- One requirement = one user story + a numbered list of EARS criteria.
- Every criterion must be **testable** — if you can't write the assertion, rewrite the criterion.
- Put non-functional requirements (latency, cost, security, throughput) in EARS too — not prose.

## 4. Definition of Done per artifact

**requirements.md** — user story per requirement; every criterion EARS + testable; NFRs (latency,
cost, security, throughput) are explicit criteria; no solution/tech choices leaked in.

**design.md** — has Overview, Architecture diagram, Components & Interfaces, Data Models, Error
Handling, Testing Strategy; every component traces to a requirement ID; every named API/class is
verified against `tech.md` / pinned deps / AWS docs; the chosen Strands primitive is named *with
rationale*; every failure mode has a defined behavior.

**tasks.md** — incremental and ordered so the system is testable at each step; every task cites the
requirement ID(s) it implements; coding actions only; an early task stands up a thin end-to-end
skeleton before depth is added.

## 5. Review checklist (apply before approving any spec change)

1. **Could I implement this without asking a question?** If no, it's underspecified.
2. **Does every named API exist?** Grep `.venv/`.
3. **What happens on the unhappy path?** Tool timeout, hallucinated arg, empty retrieval, 429
   throttling, partial failure of a parallel branch — each needs a defined behavior.
4. **Where is the security boundary, in IAM terms?** "Read-only" must be an IAM policy + a hook, not
   a sentence.
5. **What's the cost/latency budget, and what enforces it?** Token caps, model tiering, `max_tokens`,
   loop limits — name the mechanism.
6. **Is the multi-agent topology justified?** One well-bounded agent beats three that need a swarm.
