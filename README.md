# World Cup 2026 Toronto — Itinerary & Fan Guide Verifier

An agentic system that verifies **World Cup 2026 Toronto travel plans** against bookings, live match
schedules, and stadium policies. It ingests a **Draft Itinerary** and a **Bookings** folder, runs
three independent reviews in parallel — editorial, logistics, and rules & schedule — and produces a
per-activity verdict with citations.

It is **decision support**: it never modifies your documents. The agent's execution boundary is
strictly **read-only**. Built with **Claude Code Desktop**, on the **Strands Agents SDK** + **Gemini API**.

---

## Project structure

```
.
├── CLAUDE.md          # always-on project context for Claude Code (loads steering/)
├── steering/          # product / tech / structure context
│   ├── product.md     # what we're building and the bar for "done"
│   ├── tech.md        # VERIFIED Strands + Gemini API surface (grep'd from .venv)
│   └── structure.md   # spec workflow (EARS) + repo conventions
├── spec/              # the verifier spec — source of truth before code
│   ├── requirements.md  # EARS acceptance criteria
│   ├── design.md        # architecture, components, data models, error handling, tests
│   └── tasks.md         # incremental, test-first implementation plan
├── src/verifier/      # implementation (in progress)
├── tests/             # tests
├── .mcp.json          # local MCP servers (fetch, filesystem)
├── start-mcp.sh       # manual MCP launcher (debugging)
└── archive/           # parked: 3 other specs + interview-prep docs
```

---

## The spec

Start in [`spec/requirements.md`](spec/requirements.md) → [`spec/design.md`](spec/design.md) →
[`spec/tasks.md`](spec/tasks.md). Every design decision names an API verified to exist in pinned
deps (`strands_agents==1.42.0`, `google-genai==1.75.0`). See [`steering/tech.md`](steering/tech.md).

---

## Prerequisites

- **`GOOGLE_API_KEY`** — set in your environment (get one at aistudio.google.com). This is the
  google-genai SDK default. All three reviewer agents use `GeminiModel(model_id="gemini-2.5-flash")`.
- **Python venv** — all deps are in `.venv/`. Activate: `source .venv/bin/activate`.

---

## MCP sandbox

Two local MCP servers in `.mcp.json` (Claude Code launches them automatically):

- **`fetch`** — HTTP → Markdown; used for live match schedules and stadium policy pages (rules reviewer).
- **`filesystem`** — scoped to this project; reads local itinerary + booking fixtures.

Manual debugging:
```bash
./start-mcp.sh fetch
./start-mcp.sh filesystem
```
