"""Planning, prompt and PR-body helper for the doc-sync workflow.
Always run with `python3 -I`. Subcommands:

  plan <name> <remote> <base> <detect.json> <sidebar.json|-> <state-dir> <out-dir>
      Turn one repo's detection into PR units. Writes <out-dir>/units.json
      (one entry per PR to open), <out-dir>/snapshot.json (the snapshot PR) and
      <out-dir>/state-proposal.json (what finalize should record).

  prepare <unit.json> <run-dir>
      In the repo checkout (cwd): write each page's diff to .doc-sync-bot/ and
      its Codex prompt to <run-dir>/. Prints "<n>\t<title>" per page.

  prbody <unit.json> <run-dir>         → <run-dir>/pr-body.md
  snapbody <snapshot.json> <out-file>  → body for the snapshot-refresh PR

  finalize <state-dir> <proposals-dir> <results-dir>
      Record handled page versions and the new sidebar baseline in state/.

Env: BOT_DIR, MIN_SEVERITY (default medium).
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

SEVERITY_RANK = {"none": 0, "low": 1, "medium": 2, "high": 3}
OFF_SIDEBAR = "Pages not in the sidebar"


def slugify(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")[:50] or "misc"


def load(path, default=None):
    try:
        return json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return default


def snapshot_file(doc_path):
    # Mirrors docPathToSlug() in frontend/src/lib/doc-sync/paths.ts.
    return doc_path.lstrip("/").replace("/", "__") + ".md"


# --------------------------------------------------------------------- plan
def plan(name, remote, base, detect_path, sidebar_path, state_dir, out_dir):
    detect = load(detect_path)
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    state = Path(state_dir) / name
    seen = load(state / "seen.json", {"pages": {}})["pages"]
    previous_sidebar = load(state / "sidebar.json")
    sidebar = load(sidebar_path) if sidebar_path != "-" else None
    min_rank = SEVERITY_RANK[os.environ.get("MIN_SEVERITY", "medium")]

    gh_repo = re.sub(r"^(git@github\.com:|https://github\.com/)|\.git$", "", remote)
    meta = {"repo": name, "remote": remote, "base": base, "ghRepo": gh_repo}
    where = {e["url"]: e for e in (sidebar or previous_sidebar or [])}

    units, seen_without_pr, snapshot_pages = [], {}, []

    # Drift on pages the harness already implements — one PR per sidebar section.
    by_section = {}
    for page in detect["pages"]:
        snapshot_pages.append(page)
        if seen.get(page["docPath"]) == page["sha"]:
            continue  # this exact upstream version already went into a bot PR
        if page["outcome"] != "missing" and SEVERITY_RANK.get(page["severity"], 0) < min_rank:
            seen_without_pr[page["docPath"]] = page["sha"]  # prose only: snapshot PR covers it
            continue
        section = where.get(page["docPath"], {}).get("section", OFF_SIDEBAR)
        by_section.setdefault(section, []).append(page)
    for section, pages in sorted(by_section.items()):
        units.append(dict(
            meta, kind="drift", section=section, pages=pages,
            id=f"{name}--sync-{slugify(section)}",
            branch=f"sync/doc-bot-{slugify(section)}",
            title=f"sync: {section} — {len(pages)} doc page(s) changed"[:72],
        ))

    # New sidebar entries with no route — one PR per sidebar folder.
    sidebar_note = None
    if sidebar is None:
        sidebar_note = "Sidebar could not be read today; new-page detection skipped."
    elif previous_sidebar is None:
        sidebar_note = (f"Sidebar baseline recorded ({len(sidebar)} entries). "
                        "Only sections that appear after today will get PRs.")
    else:
        covered = set(detect["covered"])
        before = {e["url"] for e in previous_sidebar}
        groups = {}
        for entry in sidebar:
            if entry["url"] in before or entry["url"] in covered:
                continue
            groups.setdefault((entry["section"], entry["folder"]), []).append(entry)
        for (section, folder), entries in sorted(groups.items()):
            label = " › ".join([section] + ([folder.replace("/", " › ")] if folder else []))
            units.append(dict(
                meta, kind="new-section", section=label,
                pages=[{"docPath": e["url"], "url": "https://docs.copilotkit.ai" + e["url"],
                        "title": e["title"], "routes": [], "severity": "new",
                        "outcome": "new"} for e in entries],
                id=f"{name}--feat-{slugify(label)}",
                branch=f"feat/doc-bot-{slugify(label)}",
                title=f"feat: add {(folder.split('/')[-1] or section)} "
                      f"({len(entries)} new doc page{'s' if len(entries) > 1 else ''})"[:72],
            ))
        current = {e["url"] for e in sidebar}
        removed = sorted(before - current)
        if removed:
            sidebar_note = "Removed from the sidebar since the last run: " + ", ".join(removed)

    for unit in units:
        (out / f"unit-{unit['id']}.json").write_text(json.dumps(unit, indent=1))
    (out / "units.json").write_text(json.dumps([u["id"] for u in units]))
    (out / "snapshot.json").write_text(json.dumps(dict(
        meta, pages=snapshot_pages, units=[
            {"title": u["title"], "branch": u["branch"], "pages": [p["docPath"] for p in u["pages"]]}
            for u in units],
        sidebarNote=sidebar_note), indent=1))
    (out / "state-proposal.json").write_text(json.dumps(dict(
        repo=name, seenWithoutPr=seen_without_pr, sidebar=sidebar,
        units={u["id"]: {"kind": u["kind"],
                         "pages": {p["docPath"]: p.get("sha") for p in u["pages"]}}
               for u in units}), indent=1))
    print(f"{name}: {len(units)} unit(s), {len(snapshot_pages)} page(s) in snapshot")


# ------------------------------------------------------------------ prepare
def prepare(unit_path, run_dir):
    unit = load(unit_path)
    run = Path(run_dir)
    run.mkdir(parents=True, exist_ok=True)
    Path(".doc-sync-bot").mkdir(exist_ok=True)
    prompts = Path(os.environ["BOT_DIR"]) / "prompts"
    template = (prompts / ("page.md" if unit["kind"] == "drift" else "new-page.md")).read_text()
    siblings = "\n".join(f"- {p['title']} — {p['url']}" for p in unit["pages"])

    for n, page in enumerate(unit["pages"], 1):
        diff_rel = f".doc-sync-bot/page-{n}.diff"
        if unit["kind"] == "drift":
            diff = subprocess.run(
                ["git", "diff", "--no-color", "--",
                 f"doc-snapshot/pages/{snapshot_file(page['docPath'])}"],
                capture_output=True, text=True, check=False).stdout
            Path(diff_rel).write_text(diff or "(no textual diff — the page now returns 404)\n")
        values = {
            "{REPO}": unit["repo"], "{TITLE}": page["title"], "{URL}": page["url"],
            "{ROUTES}": ", ".join(f"`{r}`" for r in page["routes"]) or "(none yet)",
            "{FIRST_ROUTE}": (page["routes"] or [""])[0],
            "{SEVERITY}": page["severity"], "{OUTCOME}": page["outcome"],
            "{OUTCOME_NOTE}": {"changed": "the page's content changed",
                               "missing": "the page now returns 404"}.get(page["outcome"], ""),
            "{DIFF_FILE}": diff_rel, "{SECTION}": unit["section"],
            "{SIBLINGS}": siblings, "{POSITION}": f"{n} of {len(unit['pages'])}",
        }
        prompt = template
        for key, value in values.items():
            prompt = prompt.replace(key, value)
        (run / f"page-{n}.prompt.md").write_text(prompt)
        print(f"{n}\t{page['title']}")


# ------------------------------------------------------------------- bodies
def read(path, default=""):
    try:
        return Path(path).read_text().strip()
    except OSError:
        return default


RESULT_LABEL = {
    "applied": "✅ code updated", "nochange": "➖ no code change needed",
    "failed": "❌ Codex run failed", "timeout": "⏱️ Codex timed out",
    "incomplete": "⚠️ partial edit committed",
}


def prbody(unit_path, run_dir):
    unit, run = load(unit_path), Path(run_dir)
    w = []
    if unit["kind"] == "drift":
        w.append(f"Doc pages in the **{unit['section']}** section of the sidebar changed "
                 f"upstream. Each page Codex handled has its own commit.\n")
        w.append("The matching snapshot update is in the separate `sync/doc-bot-snapshot` "
                 "PR. This PR doesn't touch `doc-snapshot/`, so the two merge independently.\n")
    else:
        w.append(f"New pages appeared in the docs sidebar under **{unit['section']}** with no "
                 "harness route yet. Codex implemented them from the published code, one "
                 "commit per page.\n")
    w.append("> Draft, opened by doc-sync-bot. Nothing here has been run in a browser. "
             "Test the routes using the README walkthrough before merging.\n")
    note = read(run / "lockfile-note")
    if note:
        w.append(f"**⚠️ Lockfile fix included:**\n{note}\n")
    w.append("| Page | Route(s) | Severity | Result |\n|---|---|---|---|")
    for n, p in enumerate(unit["pages"], 1):
        routes = ", ".join(f"`{r}`" for r in p["routes"]) or "new"
        result = RESULT_LABEL.get(read(run / f"page-{n}.result"), "❔ no result")
        w.append(f"| [{p['title']}]({p['url']}) | {routes} | {p['severity']} | {result} |")
    w.append("\n## Codex notes per page\n")
    for n, p in enumerate(unit["pages"], 1):
        summary = read(run / f"page-{n}.summary.md", "_Codex left no final message._")
        usage = read(run / f"page-{n}.usage", "not reported")
        w.append(f"<details><summary><b>{p['title']}</b> (tokens: {usage})</summary>\n\n"
                 f"{summary}\n\n</details>\n")
    w.append("Anything Codex couldn't settle without inventing code is under "
             "**Questions for the reviewer** above.\n\n## Verification (run after Codex)\n")
    ran = False
    for part in ("frontend", "backend"):
        status = read(run / f"verify-{part}.status")
        if not status:
            continue
        ran = True
        w.append(f"- {'✅' if status == 'pass' else '❌'} **{part}**: "
                 f"`{read(run / f'verify-{part}.cmd')}` — {status}")
        if status != "pass":
            w.append(f"\n<details><summary>last lines</summary>\n\n```\n"
                     f"{read(run / f'verify-{part}.tail')}\n```\n</details>\n")
    if not ran:
        w.append("- Not run (no code changes).")
    w.append(f"\n---\nCodex tokens: {read(run / 'usage-total', 'not reported')} · "
             f"run: {os.environ.get('RUN_URL', 'local')}")
    (run / "pr-body.md").write_text("\n".join(w) + "\n")


def snapbody(snapshot_path, out_file):
    snap = load(snapshot_path)
    w = ["Refreshes `doc-snapshot/` to match the live docs, using the harness's own "
         "doc-sync. Snapshot files only, no code. Code changes for these pages are in "
         "the section PRs listed below.\n",
         "This PR is force-updated on each run while it stays open, so it always "
         "reflects the latest docs.\n",
         "| Page | Severity | Outcome |\n|---|---|---|"]
    for p in snap["pages"]:
        w.append(f"| [{p['title']}]({p['url']}) | {p['severity']} | {p['outcome']} |")
    if snap["units"]:
        w.append("\n**Section PRs opened in this run:**")
        w.extend(f"- `{u['branch']}` — {u['title']}" for u in snap["units"])
    if snap.get("sidebarNote"):
        w.append(f"\n**Sidebar:** {snap['sidebarNote']}")
    w.append("\nPages rated *low* or *none* (prose only) appear here and get no section PR.")
    Path(out_file).write_text("\n".join(w) + "\n")


# ----------------------------------------------------------------- finalize
def finalize(state_dir, proposals_dir, results_dir):
    """A unit's pages count as handled only if its PR was opened (or Codex found
    nothing to change). Failed units are retried on the next run."""
    for proposal_path in Path(proposals_dir).glob("*/state-proposal.json"):
        prop = load(proposal_path)
        state = Path(state_dir) / prop["repo"]
        state.mkdir(parents=True, exist_ok=True)
        seen = load(state / "seen.json", {"pages": {}})
        seen["pages"].update(prop["seenWithoutPr"])
        retry_urls = set()
        for unit_id, unit in prop["units"].items():
            outcome = read(Path(results_dir) / unit_id / "outcome")
            if outcome in ("pr-opened", "no-changes"):
                if unit["kind"] == "drift":
                    seen["pages"].update(unit["pages"])
            elif unit["kind"] == "new-section":
                retry_urls.update(unit["pages"])
        (state / "seen.json").write_text(json.dumps(seen, indent=1, sort_keys=True) + "\n")
        if prop["sidebar"] is not None:
            kept = [e for e in prop["sidebar"] if e["url"] not in retry_urls]
            (state / "sidebar.json").write_text(json.dumps(kept, indent=1) + "\n")
        print(f"{prop['repo']}: state updated")


if __name__ == "__main__":
    command, *args = sys.argv[1:]
    {"plan": plan, "prepare": prepare, "prbody": prbody,
     "snapbody": snapbody, "finalize": finalize}[command](*args)
