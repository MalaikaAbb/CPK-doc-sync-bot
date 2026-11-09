# AGENTS.md

Instructions for coding agents (Codex and others) working in this repo. Read
`CLAUDE.md` for what this project is and how it is laid out, and
`PR_GUIDELINES.md` for branch and commit conventions. This file adds the rules
that matter most when updating the harness after a docs change, many of which
were learned the hard way.

## What this repo is for

It is a test harness for `docs.copilotkit.ai/<framework>`. Each route
implements what one doc page teaches, **as published**. The harness exists to
show whether the docs work, so a route that quietly does better than its page
is a bug in the harness.

## Non-negotiable rules

1. **Copy doc code verbatim, including its bugs.** Never correct a published
   snippet. If it fails to compile, keep it byte-for-byte and put
   `// @ts-expect-error <reason>` (or `# type: ignore[...]  # <reason>`) on the
   line above it, then record the mismatch in the README's
   *Known issues / doc-vs-implementation discrepancies* section. Never annotate
   parameters or rewrite the expression. Do not turn on
   `typescript.ignoreBuildErrors`. Prompts and config count as code.
2. **Never invent missing code.** If the page doesn't publish something the
   feature needs, don't write it. Add a doc-gap entry (see below), set the
   route's status to `partial` or `broken`, and list it under
   "Questions for the reviewer" in your final message. Leaf scaffolding the
   page needs only in order to compile (a shadcn primitive, a tiny helper hook)
   may be added, but it must be labelled as repo-authored on the route.
3. **If a working remedy already exists, keep it.** Some routes have the
   verbatim doc class in one `#region` and a remedy subclass in a separate
   `#region <name>-remedy`. Update the verbatim part from the docs. Leave the
   remedy alone unless the doc change makes it unnecessary, and then say so in
   your final message.
4. **The `.md` source is not the framework's code.** `<page>.md` holds the
   default (often LangGraph or Python) snippets. The rendered page swaps in this
   framework's own code, and pages with a demo keep the full source in the
   **Code tab**. That data is in the page's RSC response:
   `curl -s -H 'RSC: 1' <page-url>`. It contains text rows `<id>:T<hexlen>,<bytes>`,
   referenced as `"code":"$<id>"`, with the file path nearby. Embedded demos
   iframe `feature-viewer.copilotkit.ai/<integration>/feature/<demo>?view=code`.
   Treat the rendered page and Code tab as the source of truth, and use the
   `.md` diff only to find what moved.
5. **Stay in scope.** Change only what the doc change requires. No refactors,
   no dependency bumps the page doesn't ask for, no edits to unrelated routes.
6. **Never touch** `doc-snapshot/` (the bot owns it), `.env*` files (except
   `.env.example` placeholders), `node_modules/`, `.venv/` or lockfiles by hand.
   Don't commit, push or create branches; the bot script does that.
7. **Never run `next dev`, `npm run dev` or long-lived servers.** This is an
   unattended run: a server that never exits hangs the job until it times
   out. The Turbopack dev cache has also caused OOM kills in these repos.

## Dependencies and version pins

- Add packages with `npm install --allow-remote=all <pkg>` (npm 12 refuses some
  optional deps without it). Don't add that flag to `.npmrc`.
- `@ag-ui/client` / `@ag-ui/core` must be the **exact** version that the
  installed `@copilotkit/react-core` pins, or two copies get installed and
  `AbstractAgent` types break with "separate declarations of a private
  property". On any CopilotKit bump, check with
  `find node_modules -path '*@ag-ui/client/package.json' -exec grep -m1 '"version"' {} \; | sort | uniq -c`
  and pin it in `dependencies` plus `overrides` if more than one copy shows up.
- A2UI needs **zod 3** (`zod@3.25.76` at the root). Under zod 4, bindings render
  blank with no error. Don't switch to `zod/v3` imports.
- Hashbrown doc code uses `prompt` and `useUiKit({ examples })`, which were
  removed in 0.8. Keep Hashbrown at the exact version the route already uses.

## Status, gaps and the README

When a doc change affects a route, keep all of these consistent:

- `frontend/src/lib/nav-config.ts`: the route's `status`
  (`working | partial | reference | broken | not-started`) and `statusNote`.
- Doc gaps (`frontend/src/lib/doc-gaps.ts` and the backend registry's `gaps`,
  where they exist): add an entry when the page omits something, and **delete**
  an entry when the page now publishes the missing piece.
- `README.md`: the walkthrough entry for the route, the status table row, and
  the discrepancies section. Write in your own words; don't paste doc prose.
- If a route mounts its own `<CopilotKit>`, add it to the nested-provider list
  in `frontend/src/lib/inspector.ts` so only one Inspector mounts.
- If a doc page now 404s, don't delete the route. Mark it `broken`, say "doc
  page returns 404" in the status note and the README table, and keep the code.

## Verifying your change

Run checks, not servers:

- Frontend type check: `cd frontend && npx tsc --noEmit`. `next dev` hides type
  errors that `next build` catches, and the bot runs `next build` after you.
- Python backend: `cd backend && uv run python -m compileall -q .`
- Node backend: `cd backend && npm run typecheck`

Errors that come from verbatim doc code are expected. Suppress them as in
rule 1 and record them. Don't fix them.

## Your final message

The bot pastes it into the PR, so use exactly these headings:

```
### What changed in the docs
<1–3 bullets, your own words>

### What I changed
<bullets: file → what and why>   (or "Nothing — prose-only change, no code affected.")

### Doc gaps / verbatim bugs recorded
<bullets, or "None">

### Questions for the reviewer
<anything you could not decide without inventing code, or "None">

### Checks run
<command → pass/fail, with the key error line if it failed>
```
