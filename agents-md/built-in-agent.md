
## built-in-agent specifics

- **The docs are unprefixed.** This harness tracks the default docs at
  `https://docs.copilotkit.ai/<page>` (e.g. `/quickstart`, `/frontend-tools`),
  not a `/<framework>/` sub-tree. `DOCS_ROOT` in nav-config is
  `https://docs.copilotkit.ai/quickstart`.
- **There is no `backend/`.** The agent is CopilotKit's built-in agent, running
  inside the Next runtime routes under `frontend/src/app/api/`. Backend
  snippets in the docs map to those route files.
- **Hashbrown is pinned to exactly 0.7.0** (`@hashbrownai/core` and `/react`).
  The docs' Code-tab renderer uses `prompt` and `useUiKit({ examples })`, which
  0.8 removed ("Export prompt doesn't exist in target module" at bundle time).
  Don't bump it.
