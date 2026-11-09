You are adding a **new doc page** to the **{REPO}** CopilotKit test harness.
It appeared in the docs sidebar under **{SECTION}** and the harness has no
route for it yet. Follow `AGENTS.md` (already in your context) and `CLAUDE.md`.
This is an unattended run: nobody can answer questions, so put them in your
final message rather than guessing.

## The page

- **{TITLE}** — {URL}
- This is page {POSITION} of the new section. Earlier pages in the section may
  already be implemented in this checkout; build on them and keep them
  consistent. All pages in the section:
{SIBLINGS}

## What to do

1. Read the rendered page and its demo Code tab, if it has one
   (`curl -s -H 'RSC: 1' {URL}`); see AGENTS.md rule 4. That is the code to
   implement, verbatim.
2. Add the route the way CLAUDE.md Step 2/3 describes and existing routes do:
   - an entry in `frontend/src/lib/nav-config.ts`, in the nav group matching
     the docs sidebar, with `docPath`, a one-line summary in your own words,
     and an honest `status`;
   - the page under `frontend/src/app/…`;
   - a runtime route and backend agent only if the page publishes them.
3. If the page is reference material (troubleshooting, architecture, premium
   Intelligence Platform features that need a paid account), follow CLAUDE.md
   Step 3: a reference panel or a documented/mocked section, clearly marked,
   not a fake working feature.
4. Anything the page needs but doesn't publish → doc-gap entry, status
   `partial`/`broken`, and a reviewer question. Never write it yourself.
5. Add the README rows (walkthrough, status table, references).
6. Run the checks in AGENTS.md ("Verifying your change"). Don't start
   servers, don't commit.
7. End with the final-message format from AGENTS.md.
