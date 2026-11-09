You are updating the **{REPO}** CopilotKit test harness because one of the doc
pages it tracks changed upstream. Follow `AGENTS.md` (already in your context)
and `CLAUDE.md`. This is an unattended run: there is no one to answer questions,
so record them in your final message rather than guessing.

## The change

- Doc page: **{TITLE}** — {URL}
- Harness route(s): {ROUTES}
- Severity from the doc-sync diff: **{SEVERITY}** (high = code inside a fence
  changed, medium = heading or prose next to code changed)
- Outcome: **{OUTCOME}** ({OUTCOME_NOTE})
- Diff of the page's markdown source, old snapshot → new:
  `{DIFF_FILE}` (relative to the repo root)

## What to do

1. Read the diff to see what moved.
2. Get this framework's actual code for the changed parts. The `.md` diff may
   show default snippets, so fetch the rendered page and, if it has a demo, its
   Code tab (`curl -s -H 'RSC: 1' {URL}`). The rendered page and Code tab are
   authoritative (AGENTS.md rule 4).
3. Find the route's implementation: `frontend/src/app{FIRST_ROUTE}/`, its
   runtime route under `frontend/src/app/api/`, and the backend agent it uses.
4. Apply exactly what the doc change requires, following the verbatim and
   no-invention rules. If the change is prose only and nothing in the code or
   README needs to change, change nothing.
5. Update the route's status, doc gaps and README entries if they are affected.
6. Run the checks listed in AGENTS.md ("Verifying your change"). Don't start
   servers, don't commit.
7. End with the final-message format from AGENTS.md.
