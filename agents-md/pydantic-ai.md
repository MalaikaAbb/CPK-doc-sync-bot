
## pydantic-ai specifics

- Docs root: `https://docs.copilotkit.ai/pydantic-ai`. Backend: Python with `uv`.
- **Keep the nested Hashbrown override.** The frontend pins `@ag-ui/*` to 1.0.1
  globally, and `@hashbrownai/core` 0.6.x needs `@ag-ui` 0.0.59 (it imports
  `EventSchemas`, which 1.0 removed), so `overrides` contains
  `"@hashbrownai/core": { "@ag-ui/core": "0.0.59", "@ag-ui/client": "0.0.59" }`.
  Removing it breaks the Hashbrown route at bundle time; tsc stays silent.
- zod stays at `3.25.76` for A2UI.
