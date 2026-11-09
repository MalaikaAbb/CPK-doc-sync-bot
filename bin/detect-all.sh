#!/usr/bin/env bash
# Job 1. For every repo in repos.conf (or just $1): detect doc drift and new
# sidebar sections, plan the PR units, and open/refresh the snapshot PR and the
# one-time AGENTS.md PR. No Codex here.
#
# Writes $WORK_ROOT/out/<repo>/{detect,sidebar,units,snapshot,state-proposal}.json,
# unit-<id>.json, and $WORK_ROOT/results/<id>/outcome for units skipped because
# a PR for them already exists.
set -uo pipefail
source "$BOT_DIR/bin/lib.sh"

ONLY=${1:-}
OUT="$WORK_ROOT/out"; RESULTS="$WORK_ROOT/results"
mkdir -p "$OUT" "$RESULTS"
FAILED=0

detect_repo() {
  local name=$1 remote=$2 base=$3 prefix=${4:-}
  local dir="$WORK_ROOT/repos/$name" out="$OUT/$name"
  LOG_TAG=$name
  mkdir -p "$out"
  clone_repo "$remote" "$base" "$dir" || return 1
  local base_sha; base_sha=$(git -C "$dir" rev-parse HEAD)

  log "running the repo's doc-sync"
  run_doc_sync "$dir" "$out/detect.json" || { log "doc-sync failed"; return 1; }
  read -r ok message < <($PY -c 'import json,sys; d=json.load(open(sys.argv[1]))
print(str(d["ok"]).lower(), d["message"])' "$out/detect.json")
  [[ "$ok" == "true" ]] || { log "doc-sync aborted: $message"; return 1; }
  log "$message"

  local docs_root sidebar="-"
  docs_root=$($PY -c 'import json,sys; print(json.load(open(sys.argv[1]))["docsRoot"])' "$out/detect.json")
  if $PY "$BOT_DIR/bin/sidebar.py" "$docs_root" ${prefix:+"$prefix"} > "$out/sidebar.json" 2> "$out/sidebar.err"; then
    sidebar="$out/sidebar.json"
  else
    log "sidebar not read: $(cat "$out/sidebar.err")"
  fi

  $PY "$BOT_DIR/bin/helper.py" plan "$name" "$remote" "$base" \
      "$out/detect.json" "$sidebar" "$BOT_DIR/state" "$out" || return 1
  local gh_repo
  gh_repo=$($PY -c 'import json,sys; print(json.load(open(sys.argv[1]))["ghRepo"])' "$out/snapshot.json")

  # Units whose PR already exists aren't redone. A closed, unmerged new-section
  # PR means "not wanted", so it's never reopened.
  local id branch kind state keep=()
  for id in $($PY -c 'import json,sys; print(" ".join(json.load(open(sys.argv[1]))))' "$out/units.json"); do
    read -r branch kind < <($PY -c 'import json,sys; u=json.load(open(sys.argv[1])); print(u["branch"], u["kind"])' "$out/unit-$id.json")
    state=$(pr_state "$gh_repo" "$branch")
    mkdir -p "$RESULTS/$id"
    if [[ "$state" == "open" ]]; then
      log "skip $branch: PR already open"; echo pr-open > "$RESULTS/$id/outcome"
    elif [[ "$state" == "closed" && "$kind" == "new-section" ]]; then
      log "skip $branch: PR was closed without merging"; echo declined > "$RESULTS/$id/outcome"
    else
      keep+=("$id")
    fi
  done
  $PY -c 'import json,sys; print(json.dumps(sys.argv[2:]))' x "${keep[@]}" > "$out/units.json"
  log "${#keep[@]} unit(s) to apply"

  [[ "${DRY_RUN:-false}" == "true" ]] && { log "dry run: no snapshot or AGENTS.md PR"; return 0; }

  # Snapshot-refresh PR: doc-snapshot/ only, force-updated while open.
  # (Gated on real page changes: doc-sync rewrites syncedAt on every run.)
  local changed
  changed=$($PY -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["pages"]))' "$out/detect.json")
  if [[ "$changed" -gt 0 ]]; then
    git -C "$dir" checkout --quiet -B sync/doc-bot-snapshot
    git -C "$dir" add doc-snapshot
    git -C "$dir" commit --quiet -m "sync: refresh doc-snapshot ($(date -u +%F))"
    push_branch "$dir" "$gh_repo" sync/doc-bot-snapshot
    $PY "$BOT_DIR/bin/helper.py" snapbody "$out/snapshot.json" "$out/snapshot-body.md"
    log "snapshot PR: $(upsert_pr "$gh_repo" "$base" sync/doc-bot-snapshot \
          "sync: refresh doc-snapshot" "$out/snapshot-body.md")"
  fi

  # One-time AGENTS.md PR, so Codex's rules live in the repo itself.
  if [[ ! -f "$dir/AGENTS.md" && "$(pr_state "$gh_repo" docs/doc-bot-agents-md)" == "none" ]]; then
    git -C "$dir" checkout --quiet -f -B docs/doc-bot-agents-md "$base_sha"
    git -C "$dir" clean -fdq
    agents_md "$name" > "$dir/AGENTS.md"
    git -C "$dir" add AGENTS.md
    git -C "$dir" commit --quiet -m "docs: add AGENTS.md for the Codex doc-sync bot"
    push_branch "$dir" "$gh_repo" docs/doc-bot-agents-md
    printf 'Adds `AGENTS.md`: the rules Codex follows when doc-sync-bot updates this harness (verbatim doc code, no invented code, version pins, how to verify).\n\nUntil this merges, the bot gives Codex the same file at run time.\n' > "$out/agents-body.md"
    log "AGENTS.md PR: $(upsert_pr "$gh_repo" "$base" docs/doc-bot-agents-md \
          "docs: add AGENTS.md for the doc-sync bot" "$out/agents-body.md")"
  fi
}

while read -r NAME REMOTE BASE PREFIX _; do
  [[ -z "${NAME:-}" || "$NAME" == \#* ]] && continue
  [[ -n "$ONLY" && "$NAME" != "$ONLY" ]] && continue
  echo "::group::$NAME"
  if ! detect_repo "$NAME" "$REMOTE" "$BASE" "${PREFIX:-}"; then
    echo "::error::$NAME: detection failed"; FAILED=1
    rm -rf "$OUT/$NAME"   # no plan → finalize leaves its state untouched
  fi
  echo "::endgroup::"
done < "$BOT_DIR/repos.conf"

# Matrix for job 2: [{"id": ..., "repo": ...}, ...]
$PY - "$OUT" > "$WORK_ROOT/matrix.json" <<'EOF'
import json, sys
from pathlib import Path
units = []
for f in sorted(Path(sys.argv[1]).glob("*/units.json")):
    units += [{"id": i, "repo": f.parent.name} for i in json.loads(f.read_text())]
print(json.dumps(units))
EOF
log "matrix: $(cat "$WORK_ROOT/matrix.json")"
exit $FAILED
