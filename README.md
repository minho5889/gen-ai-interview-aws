# Medical Content Review (MLR) — Agentic Compliance Review

An agentic system that automates the **first pass** of Medical, Legal, and Regulatory (MLR) review
for pharmaceutical / medical-device marketing. It ingests a marketing **Content** asset and a
supporting **Reference** pack, runs three independent reviews in parallel — editorial,
internal-evidence, and external-evidence — and produces a per-claim verdict with citations.

It is **decision support**: it never publishes; a human MLR reviewer makes the final call. The
agent's execution boundary is strictly **read-only**.

Built with **Claude Code Desktop**, on the **Strands Agents SDK** + Amazon Bedrock.

---

## Project structure

```
.
├── CLAUDE.md          # always-on project context for Claude Code (loads steering/)
├── steering/          # product / tech / structure context
│   ├── product.md     # what we're building and the bar for "done"
│   ├── tech.md        # VERIFIED Strands/AgentCore API surface (grep'd from .venv)
│   └── structure.md   # spec workflow (EARS) + repo conventions
├── spec/              # the MLR spec — the source of truth before code
│   ├── requirements.md  # EARS acceptance criteria
│   ├── design.md        # architecture, components, data models, error handling, tests
│   └── tasks.md         # incremental, test-first implementation plan
├── src/mlr/           # implementation (in progress)
├── tests/             # tests
├── .mcp.json          # local MCP servers (fetch, filesystem)
├── start-mcp.sh       # manual MCP launcher (debugging)
└── archive/           # parked: 3 other specs + interview-prep docs (not part of MLR)
```

---

## The spec

Start in [`spec/requirements.md`](spec/requirements.md) → [`spec/design.md`](spec/design.md) →
[`spec/tasks.md`](spec/tasks.md). The discipline: the spec is agreed before code is written, and
every design decision names an API that is **verified to exist** in the pinned dependencies
(`strands_agents==1.42.0`) — see [`steering/tech.md`](steering/tech.md).

---

## MCP sandbox

Two local MCP servers, registered in `.mcp.json` (Claude Code launches them automatically and will
prompt to approve project MCP servers on first use):

- **`fetch`** — HTTP → Markdown; stand-in for fetching PubMed / openFDA pages (external evidence).
- **`filesystem`** — scoped to this project; reads local Content / Reference fixtures.

A PubMed/openFDA MCP server and an S3 (internal-evidence) tool are added during the build — see the
External / Internal Evidence reviewers in the design.

Manual debugging:
```bash
./start-mcp.sh fetch
./start-mcp.sh filesystem
```
