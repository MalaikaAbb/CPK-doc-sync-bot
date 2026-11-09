
## aws-strands-py specifics

- Docs root: `https://docs.copilotkit.ai/strands`. Backend: Python with `uv`
  (`backend/pyproject.toml`, code under `backend/src/`).
- README layout: §7 walkthrough, §8 status table, §9 known issues.
- **Hooks go on the wrapper.** A `HookProvider` passed to
  `strands.Agent(hooks=[...])` never fires, because ag-ui-strands builds a fresh
  agent per thread and drops `hooks`. Remedy hooks belong on
  `StrandsAgent(agent=..., name=..., hooks=[...])`. If a doc snippet puts hooks
  on `Agent(...)`, keep it verbatim and record the finding.
- **A2UI fixed schema:** only the fixed-schema route is kept. It runs the
  showcase `display_flight` + `flight_schema.json` from the CopilotKit GitHub
  showcase tree, flagged on the route as "from GitHub, not the doc page".
  The Code-tab `generate_a2ui` variant was removed on purpose. **Don't re-add
  it**, even if the page still shows it. Note any change to it in the README
  instead.
- `backend/docs_verbatim/` is byte-exact reference material: update it from the
  docs, but never import it.
