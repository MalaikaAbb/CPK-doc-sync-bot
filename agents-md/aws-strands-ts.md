
## aws-strands-ts specifics

- Docs root: `https://docs.copilotkit.ai/strands-typescript`. Backend: Node /
  TypeScript (`backend/`, run with `tsx`, checked with `npm run typecheck`).
- README layout differs from the other repos: §6 walkthrough, §7 status table,
  §9 known issues.
- **The backend pins `@ag-ui/*` to 0.0.59 on purpose.** `@ag-ui/aws-strands`
  0.3.0 imports `RunAgentInputSchema` from the `@ag-ui/core` root, and core 1.0
  moved it to `@ag-ui/core/schemas`, so the server crashes at startup. The
  backend is its own process and doesn't need to match the frontend's
  CopilotKit pin. Don't "align" the two.
- **Hashbrown and json-render keep only their fixed variants**, marked
  working. The as-published variants were removed on purpose. Don't re-add
  them. If the published code changes, update the README's discrepancy entries
  and adjust the fixed variant only where it mirrors the published code.
- Several pages publish `<!-- setup skipped: … is not bundled for
  strands-typescript -->` where the backend snippet should be. That gap is
  tracked in `frontend/src/lib/doc-gaps.ts` (`setup-skipped`). Remove a page
  from that entry when it gains a real Strands backend section.
- `backend/docs_verbatim/` is byte-exact reference material: update it from the
  docs, but never import it.
