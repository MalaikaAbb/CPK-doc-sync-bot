
## claude-sdk-typescript specifics

- Docs root: `https://docs.copilotkit.ai/claude-sdk-typescript`. Backend: Node /
  TypeScript (`npm run typecheck`).
- **Interrupts (`/human-in-the-loop/governed-actions`):** same shape as the
  Python adapter. Deferred tools must be stdio MCP, resume with
  `{behavior: "allow" | "deny"}` (always include a reason with deny), and
  metadata is `{source, toolName, input}`. In TypeScript, `deferTools` exists
  only inside `sessionRecovery: { store, resolveProfile, profile, deferTools }`,
  so the repo supplies an in-memory store
  (`backend/src/agents/memory-session-binding-store.ts`). The doc's `{approved}`
  payload produces RUN_ERROR; the route shows the doc version and the fixed
  version side by side. Keep both.
- `useInterrupt` writes to one global slot, so never put two interrupt demos on
  one page.
