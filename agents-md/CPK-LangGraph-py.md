
## CPK-LangGraph-py specifics

- Docs root: `https://docs.copilotkit.ai/langgraph-python`. Backend: Python with `uv`.
- LangGraph is the docs' default framework, so the `.md` snippets usually *are*
  this framework's code. Still check the rendered page's Python tab, since a
  page can carry both languages.
- Keep deprecated-but-working LangGraph APIs exactly as published (for example
  `StateGraph(..., input=/output=)` and `config_schema=`), and note the
  deprecation warning in the README instead of modernising the call.
