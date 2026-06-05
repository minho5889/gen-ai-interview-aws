# Medical Content Review (MLR) — Project Context

> Claude Code auto-loads this file into every session. It `@import`s the `steering/` docs at the
> bottom so the full context is always present.

## What this is
A single-focus project: an agentic **Medical, Legal & Regulatory (MLR) review** system that
checks pharma/medical-device marketing claims against evidence and produces per-claim verdicts with
citations. Decision support only — read-only, never publishes. Built with **Claude Code Desktop** on
the **Strands Agents SDK** + Amazon Bedrock.

The spec is the source of truth: `spec/requirements.md` → `spec/design.md` → `spec/tasks.md`.
Implementation lives in `src/mlr/`, tests in `tests/`.

## Non-negotiable rules
1. **Verify, don't vibe.** Before naming any Strands/AWS API in the spec or in code, grep the
   installed source under `.venv/lib/python3.13/site-packages/strands/` (and friends). If it can't be
   verified, say so and tag it _(verify)_. Hallucinated APIs are the failure mode we exist to avoid.
2. **Spec before code.** EARS requirements → traceable design → incremental, test-first tasks. See
   `steering/structure.md`.
3. **One orchestration spine.** Strands + AgentCore is the spine. Use other ecosystem pieces (e.g.
   LangChain) only as leaf *libraries*, never as a second framework. See `steering/tech.md`.
4. **LLM for judgment, code for arithmetic.** Deterministic logic (segmentation, the synthesis
   verdict rule) is pure, testable functions — not agents.
5. **Read-only boundary.** No tool may write/update/delete. Enforced by the `ReadOnlyGuard` hook
   (`BeforeToolCallEvent` + `cancel_tool`), Bedrock Guardrails, and least-privilege IAM.

## Repo map
- `spec/` — the MLR spec (requirements / design / tasks)
- `steering/` — product / tech / structure context (imported below)
- `src/mlr/`, `tests/` — implementation + tests
- `.mcp.json` — local MCP servers (fetch, filesystem)
- `archive/` — parked specs + interview-prep docs; **not** part of this project, don't touch unless asked

## Steering (always in context)
@steering/product.md
@steering/tech.md
@steering/structure.md
