
## google-adk specifics

- Docs root: `https://docs.copilotkit.ai/google-adk`. Backend: Python with `uv`.
- **Tool-transport generative UI is broken on Gemini.** The Components &
  surfaces tool transport adds a `render_ui` client tool whose `operations`
  items are property-less objects. `ag_ui_adk` passes that to Gemini as an
  object with no properties, and Gemini returns garbage the runtime rejects.
  Prompt changes don't help. The user's decision: document it and mark the
  route Broken; don't add STRING-typed glue. (Markdown transport works.)
- **One Inspector per page:** routes that mount their own `<CopilotKit>` must be
  listed in `NESTED_PROVIDER_ROUTES` in `frontend/src/lib/inspector.ts`, or two
  Inspectors mount and the tab hangs.
- Hashbrown (`^0.6.1`) has a latent `@ag-ui` version clash. If a global
  `@ag-ui` override is ever added, add a nested override
  `"@hashbrownai/core": { "@ag-ui/core": "0.0.59", "@ag-ui/client": "0.0.59" }`
  as pydantic-ai does.
