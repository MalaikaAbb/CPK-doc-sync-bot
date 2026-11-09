
## ms-agent-framework-py specifics

- Docs root: `https://docs.copilotkit.ai/ms-agent-python`. Backend: Python with `uv`.
- **A2UI dynamic schema gotcha:** with `<CopilotKit a2ui={{ catalog }}>` and
  `injectA2UITool: true`, the adapter puts all forwarded A2UI context into the
  planner prompt, and the catalog's component-schema / generation-guidelines
  entries make `generate_a2ui` fail with "Argument parsing failed".
  `includeSchema: false` stops that but then needs runtime
  `a2ui.defaultCatalogId`, or the surface falls back to the basic catalog
  ("Catalog not found"). Keep the doc's form verbatim, and record this as a
  discrepancy if a doc change touches it.
- An endpoint's `a2ui_config` is ignored when the agent is already an
  `AgentFrameworkAgent`.
