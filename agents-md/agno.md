
## agno specifics

- Docs root: `https://docs.copilotkit.ai/agno`. Backend: Python with `uv`
  (`backend/pyproject.toml`). The frontend dev port is 3010.
- README layout: §7 walkthrough, §8 status table, §9 known issues.
- **Agno 3 can't run the docs' demo server.** The Code tab's
  `src/agent_server.py` imports `agno.os.interfaces.agui.utils.*` helpers that
  were removed in agno 3.x, plus private `_shared.*` / `agents._*` modules. This
  repo deliberately mounts the stock `AGUI(agent=..., prefix=...)` router
  instead. Keep doing that. Don't port or downgrade, and record any new
  published custom route as a discrepancy.
- Frontend-tool resume through the stock router **requires a `db`** on the
  agent, or it fails with `RUN_ERROR: Frontend tool resume requires a database`.
  Per-tool `STATE_DELTA` needs `jsonpatch` (the `agno[agui]` extra), which the
  Quickstart's install line leaves out.
- `backend/docs_verbatim/` holds published code that can't run as-is. It is
  byte-exact reference material: update it from the docs, but never import it.
