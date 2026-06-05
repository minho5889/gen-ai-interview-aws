# World Cup 2026 Toronto — Itinerary & Fan Guide Verifier

> Claude Code auto-loads this file into every session. It `@import`s the `steering/` docs at the
> bottom so the full context is always present.

## What this is
A single-focus project: an agentic **travel itinerary & fan guide verification** system that checks
World Cup 2026 Toronto trip plans against bookings (Google Drive), live match schedules, and stadium
policies — producing per-activity verdicts with citations. Decision support only — read-only, never
modifies documents. Built with **Claude Code Desktop** on the **Strands Agents SDK** + **Gemini API**.

The spec is the source of truth: `spec/requirements.md` → `spec/design.md` → `spec/tasks.md`.
Implementation lives in `src/verifier/`, tests in `tests/`.

## Non-negotiable rules
1. **Verify, don't vibe.** Before naming any Strands/Google API in the spec or in code, grep the
   installed source under `.venv/lib/python3.13/site-packages/strands/` (and friends). If it can't be
   verified, say so and tag it _(verify)_. Hallucinated APIs are the failure mode we exist to avoid.
2. **Spec before code.** EARS requirements → traceable design → incremental, test-first tasks. See
   `steering/structure.md`.
3. **One orchestration spine.** Strands is the spine. Model provider: `GeminiModel` (google-genai
   1.75.0, `GOOGLE_API_KEY` env var). See `steering/tech.md`.
4. **LLM for judgment, code for arithmetic.** Deterministic logic (segmentation, synthesis verdict
   rule) is pure, testable functions — not agents.
5. **Read-only boundary.** No tool may write/update/delete. Enforced by the `ReadOnlyGuard` hook
   (`BeforeToolCallEvent` + `cancel_tool`).

## Repo map
- `spec/` — the verifier spec (requirements / design / tasks)
- `steering/` — product / tech / structure context (imported below)
- `src/verifier/`, `tests/` — implementation + tests
- `.mcp.json` — local MCP servers (fetch, filesystem)
- `archive/` — parked specs + interview-prep docs; **not** part of this project

## Steering (always in context)
@steering/product.md
@steering/tech.md
@steering/structure.md
