
## CPK-LangGraph-TS specifics

- Docs root: `https://docs.copilotkit.ai/langgraph-typescript`. Backend: Node / TypeScript (`npm run typecheck`).
- LangGraph is the docs' default framework, so the `.md` snippets usually *are*
  this framework's code. Still check the rendered page's TypeScript tab, since a
  page can carry both languages.
- Keep deprecated-but-working LangGraph APIs exactly as published (for example
  `StateGraph(..., input=/output=)` and `config_schema=`), and note the
  deprecation warning in the README instead of modernising the call.
