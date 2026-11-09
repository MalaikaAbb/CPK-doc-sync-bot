# doc-sync-bot

A GitHub Actions workflow that keeps the CopilotKit test harness repos in step
with `docs.copilotkit.ai`. Every day at **11:00 PKT** it checks each harness
against the live docs, has **Codex** apply what changed, and opens **draft PRs**
for you to review. It never pushes to `main`.

## What happens on each run

```
detect   (one job, every repo in repos.conf, ~10 s each, no AI)
  ├─ run the harness's own doc-sync  → which tracked doc pages changed
  ├─ read the docs sidebar           → which sidebar pages are new since yesterday
  ├─ open/refresh the snapshot PR    (doc-snapshot/ only)
  └─ plan one unit per PR:
       • drift:       changed pages, grouped by sidebar section   → sync/doc-bot-<section>
       • new section: new sidebar pages with no route, per folder → feat/doc-bot-<section>-<folder>

apply    (one job per unit, 3 at a time)
  ├─ npm ci / uv sync
  ├─ Codex, one doc page at a time → one commit per page
  ├─ next build + backend check     (result goes in the PR body)
  └─ push the branch and open a draft PR

finalize
  └─ record in state/ which page versions are handled and the new sidebar baseline
```

### The PRs you'll get, per harness repo

| PR | Branch | Contains | When |
|---|---|---|---|
| Snapshot refresh | `sync/doc-bot-snapshot` | `doc-snapshot/` only | Any tracked page changed. Force-updated daily while open. |
| Section drift | `sync/doc-bot-<section>` | Code + README for that sidebar section's changed pages | Code or headings changed (Medium/High severity) |
| New section | `feat/doc-bot-<section>-<folder>` | New routes, nav entries and README rows | A sidebar folder gained pages the harness doesn't cover |
| AGENTS.md | `docs/doc-bot-agents-md` | The rules Codex follows | Once, if the repo has no `AGENTS.md` |

Section PRs never touch `doc-snapshot/`, so you can merge them and the snapshot
PR in any order. Several section PRs in one repo all edit `nav-config.ts` and
`README.md`, so after merging one you may need to rebase the next (GitHub's
"Update branch" button, or resolve locally).

### Rules the bot follows

- **Never the same change twice.** `state/<repo>/seen.json` stores the upstream
  hash of every page version already turned into a PR. A page only comes back
  when the docs change it again.
- **One PR per branch.** If a unit's PR is still open, the unit is skipped.
- **Closed means no.** If you close a new-section PR without merging it, that
  section is never proposed again.
- **Prose-only edits** (Low/None severity) go into the snapshot PR only; Codex
  doesn't run for them. Change `MIN_SEVERITY` to adjust this.
- **Failures are retried.** If Codex fails on every page of a unit, nothing is
  recorded and the unit runs again the next day. Partial work is committed as
  `wip:` and marked ⚠️ in the PR.
- **The sidebar starts from a baseline.** On the first run, each repo's current
  sidebar is recorded as known. Only sections that appear *after* that get PRs.
  This avoids PRs for pages you've deliberately left out (Troubleshooting,
  premium Intelligence, Contributing).

## One-time setup

### 1. Create the central repo (public)

Public means unlimited free Actions minutes on standard runners. The repo holds
only scripts; keys stay in encrypted secrets.

```bash
cd ~/copilotkit/doc-sync-bot
git init -b main && git add . && git commit -m "doc-sync-bot: initial version"
gh repo create MalaikaAbb/doc-sync-bot --public --source . --push
# (no gh? create the empty public repo on github.com, then:
#  git remote add origin https://github.com/MalaikaAbb/doc-sync-bot.git && git push -u origin main)
```

### 2. Create a GitHub token for the harness repos

github.com → **Settings → Developer settings → Personal access tokens →
Fine-grained tokens → Generate new token**

- **Resource owner:** MalaikaAbb
- **Repository access:** *Only select repositories*. Pick every harness repo
  listed in `repos.conf`. Add new repos here when you add them to `repos.conf`.
- **Permissions → Repository:** *Contents*: Read and write · *Pull requests*:
  Read and write. *Metadata: Read* is added automatically.
- **Expiration:** your choice. Put a reminder in your calendar; when it expires
  the detect job fails with a 401.

### 3. Add the secrets

In **MalaikaAbb/doc-sync-bot → Settings → Secrets and variables → Actions →
Secrets**:

| Secret | Value |
|---|---|
| `HARNESS_PAT` | The token from step 2 |
| `OPENAI_API_KEY` | An OpenAI API key with credit. Codex is billed per token on it. |

### 4. Optional settings

Same page, **Variables** tab. Everything has a default:

| Variable | Default | What it does |
|---|---|---|
| `CODEX_MODEL` | Codex's default | Model to use |
| `CODEX_EFFORT` | Codex's default | `low` / `medium` / `high` reasoning effort |
| `CODEX_TIMEOUT` | `2400` | Seconds allowed per doc page |
| `CODEX_VERSION` | `0.167.0` | Codex CLI version installed on the runner |
| `MIN_SEVERITY` | `medium` | `high` = only code-fence changes reach Codex; `low` = everything |

Also check **Settings → Actions → General → Workflow permissions** allows
*Read and write*. The finalize job commits `state/` back to this repo.

### 5. First run: dry run, one repo

**Actions → doc-sync → Run workflow**, with *repo* = `agno` and *dry run* ticked.

It detects, plans and runs Codex, but pushes nothing. Download the run's
artifacts to read the planned units (`out/agno/unit-*.json`), Codex's notes
(`page-*.summary.md`) and the PR bodies it would have opened (`pr-body.md`).

Then run it again without *dry run* for `agno`, review the PRs, and after that
let the daily schedule take over for all repos.

**Expect a large first run.** On 2026-11-09 every harness was behind the live
docs, by 7 pages (deepagents-ts) up to 31 (CPK-LangGraph-py). Across all 15
repos that comes to roughly **75 section PRs, plus 15 snapshot PRs and 15
AGENTS.md PRs**, and one Codex run per changed page. Later runs only pick up
what changed since. To keep the first run manageable, run the workflow by hand
for one repo at a time (*repo* input) and review those PRs before the next.
The daily schedule then only finds new changes.

## Adding more harness repos

`repos.conf` already lists all 15 React harnesses in `~/copilotkit/optimizations`,
and each has its own notes in `agents-md/<name>.md`. To add another:

1. Add a line to `repos.conf`: `<name> <https remote> <base branch> [<sidebar prefix>]`.
   The prefix is only needed when the harness doesn't track a `/<framework>/`
   docs tree: built-in-agent uses `/` (the unprefixed docs).
2. Give the token from step 2 access to that repo.
3. Optional: add `agents-md/<name>.md` with that framework's gotchas. The shared
   rules in `agents-md/common.md` apply to every repo.

Requirement: the repo must have the harness doc-sync module at
`frontend/src/lib/doc-sync/` (actions.ts, paths.ts, store.ts…) and
`frontend/src/lib/nav-config.ts`. A repo without `backend/` (built-in-agent,
mastra) works; only the backend check is skipped. The Angular harnesses
(`~/copilotkit/angular-optimizations`) use a different variant
(`run-sync.ts` behind an Express endpoint) and need a small adapter in
`detect/` before they can be added.

The workflow scales by repo count with no other changes: detection stays one
job, and only repos with changes get apply jobs. Raise `max-parallel` in the
workflow if 3 at a time is too slow.

## Cost and limits

- **No doc changes:** about 1–2 runner minutes for detection, no OpenAI tokens.
- **Per changed page:** one Codex run, typically a few hundred thousand to a
  few million input tokens (mostly cached) and 10–40k output. Each PR body shows
  the exact count per page.
- **Runner time:** each apply job installs dependencies and runs `next build`.
  Expect roughly 10–40 minutes per unit. The job limit is set to 5 hours.

## What it can't do (check these when reviewing)

- **No browser testing.** The PR proves the code builds; it doesn't prove the
  agent behaves. Test the routes with the README walkthrough.
- **Drift detection reads each page's `.md` source.** A change that exists only
  in a page's rendered framework snippet or demo Code tab isn't seen until the
  `.md` also changes. Codex does read the rendered page and Code tab when it
  applies a change.
- **Codex has full shell access on the runner** (`danger-full-access`: the
  Linux sandbox isn't reliable on GitHub runners). The runner is a throwaway VM,
  and the Codex step has no GitHub token: checkout credentials aren't kept, and
  the push happens in a separate step.
- **GitHub may start scheduled runs late** (usually minutes). Each run commits
  `state/last-run`, which also stops GitHub disabling the schedule after 60
  days without activity.

## Files

```
.github/workflows/doc-sync.yml   the workflow (schedule, three jobs)
repos.conf                       harness repos to process
bin/detect-all.sh                job 1: detection, planning, snapshot + AGENTS.md PRs
bin/apply-unit.sh                job 2: Codex per page, commits, build check (no GitHub token)
bin/open-pr.sh                   job 2: push + draft PR (no Codex)
bin/helper.py                    planning, prompts, PR bodies, state updates
bin/sidebar.py                   reads the docs sidebar from the page's RSC payload
bin/usage.py                     sums Codex token usage for the PR body
bin/lib.sh                       shared shell helpers
detect/detect.mts (+ shims/)     runs the harness's own doc-sync outside Next.js
prompts/page.md, new-page.md     what Codex is asked to do per page
agents-md/                       AGENTS.md content: common rules + per-repo notes
state/<repo>/                    seen.json (handled page versions), sidebar.json (baseline)
```

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| detect fails with 401/403 | `HARNESS_PAT` expired or lacks that repo. Regenerate it, or add the repo to it. |
| `doc-sync aborted: Upstream did not return markdown` | The docs site changed its `.md` handling. The harness doc-sync refuses to overwrite the snapshot; fix `fetch-docs.ts` in the harness. |
| `sidebar not read` in the log | The docs site changed its page-tree format. Drift PRs still work; fix `bin/sidebar.py`. |
| Apply job fails at `npm ci` | The harness's lockfile is out of sync with `package.json` on `main`. Fix that in the harness repo. |
| PR says ❌ for `next build` | Read the "last lines" block. Usually a verbatim doc bug that needs `@ts-expect-error` (AGENTS.md rule 1) or a version pin. Fix it on the PR branch. |
| The same section PR keeps coming back | You merged the code but `seen.json` didn't record it (the run failed after the PR opened). Remove the stale branch; the next run updates state. |
| Want to re-propose a closed new-section PR | Delete its branch on the harness repo and remove its URLs from `state/<repo>/sidebar.json`. |
