#!/usr/bin/env bash
# Job 2, step 1: apply one PR unit with Codex. Runs with OPENAI_API_KEY but
# deliberately WITHOUT any GitHub token, since Codex executes commands here.
#   apply-unit.sh <unit.json>
# Leaves the commits in $WORK_ROOT/repos/<repo>; open-pr.sh pushes them.
set -euo pipefail
source "$BOT_DIR/bin/lib.sh"

UNIT=$1
read -r REPO REMOTE BASE KIND ID < <($PY -c 'import json,sys; u=json.load(open(sys.argv[1]))
print(u["repo"], u["remote"], u["base"], u["kind"], u["id"])' "$UNIT")
LOG_TAG=$ID
DIR="$WORK_ROOT/repos/$REPO"
RUN="$WORK_ROOT/results/$ID"
mkdir -p "$RUN"

clone_repo "$REMOTE" "$BASE" "$DIR"
cd "$DIR"
git rev-parse HEAD > "$RUN/base-sha"

# ------------------------------------------------------------------ deps
log "installing dependencies"
(cd frontend && npm ci --allow-remote=all --no-audit --no-fund --loglevel=error) > "$RUN/npm-frontend.log" 2>&1
if [[ -f backend/package.json ]]; then
  (cd backend && npm ci --allow-remote=all --no-audit --no-fund --loglevel=error) > "$RUN/npm-backend.log" 2>&1
elif [[ -f backend/pyproject.toml ]]; then
  (cd backend && uv sync --frozen --quiet) > "$RUN/uv.log" 2>&1
fi

# ------------------------------------------------------------ prompts
if [[ "$KIND" == "drift" ]]; then
  # Re-run the doc-sync so the working tree holds the new snapshot, take each
  # page's diff from it, then put doc-snapshot back: the section PR carries
  # code only (the snapshot has its own PR).
  run_doc_sync "$DIR" "$RUN/detect.json"
fi
# Codex reads AGENTS.md from the repo. Until the AGENTS.md PR merges, provide it
# uncommitted (excluded from git).
if [[ ! -f AGENTS.md ]]; then
  agents_md "$REPO" > AGENTS.md
  echo 'AGENTS.md' >> .git/info/exclude
fi
mapfile -t PAGES < <($PY "$BOT_DIR/bin/helper.py" prepare "$UNIT" "$RUN")
git checkout --quiet -- doc-snapshot && git clean -fdq -- doc-snapshot

# ------------------------------------------------------------------ codex
printenv OPENAI_API_KEY | codex login --with-api-key > /dev/null
CODEX=(codex -a never)
[[ "${CODEX_WEB_SEARCH:-true}" == "true" ]] && CODEX+=(--search)
CODEX+=(exec -s "${CODEX_SANDBOX:-danger-full-access}" -C "$DIR" --json --color never)
[[ -n "${CODEX_MODEL:-}"  ]] && CODEX+=(-m "$CODEX_MODEL")
[[ -n "${CODEX_EFFORT:-}" ]] && CODEX+=(-c "model_reasoning_effort=\"$CODEX_EFFORT\"")

ANY_CODE=0
for row in "${PAGES[@]}"; do
  N=${row%%$'\t'*}; TITLE=${row#*$'\t'}
  log "codex [$N/${#PAGES[@]}]: $TITLE"
  set +e
  timeout "${CODEX_TIMEOUT:-2400}" "${CODEX[@]}" -o "$RUN/page-$N.summary.md" - \
    < "$RUN/page-$N.prompt.md" > "$RUN/page-$N.events.jsonl" 2> "$RUN/page-$N.stderr"
  RC=$?
  set -e
  $PY "$BOT_DIR/bin/usage.py" "$RUN/page-$N.events.jsonl" > "$RUN/page-$N.usage"

  # The snapshot is not Codex's to change.
  git checkout --quiet -- doc-snapshot && git clean -fdq -- doc-snapshot
  git add -A
  if git diff --cached --quiet; then
    if [[ $RC -eq 124 ]]; then echo timeout; elif [[ $RC -ne 0 ]]; then echo failed; else echo nochange; fi \
      > "$RUN/page-$N.result"
    log "  → no file changes (exit $RC)"
    continue
  fi
  ANY_CODE=1
  URL=$($PY -c 'import json,sys; print(json.load(open(sys.argv[1]))["pages"][int(sys.argv[2])-1]["url"])' "$UNIT" "$N")
  if [[ $RC -eq 0 ]]; then
    echo applied > "$RUN/page-$N.result"
    if [[ "$KIND" == "drift" ]]; then SUBJECT="sync: apply $TITLE doc changes"; else SUBJECT="feat: add $TITLE route"; fi
  else
    echo incomplete > "$RUN/page-$N.result"; SUBJECT="wip: $TITLE (Codex exit $RC, partial)"
  fi
  git commit --quiet -m "${SUBJECT:0:72}" -m "Doc page: $URL" -m "Applied by doc-sync-bot with Codex."
  log "  → committed"
done
$PY "$BOT_DIR/bin/usage.py" "$RUN"/page-*.events.jsonl > "$RUN/usage-total"

# ----------------------------------------------------------------- verify
verify() {  # verify <part> <dir> <command...>
  local part=$1 dir=$2; shift 2
  echo "$*" > "$RUN/verify-$part.cmd"
  log "verify $part: $*"
  if (cd "$dir" && timeout "${BUILD_TIMEOUT:-3600}" "$@") > "$RUN/verify-$part.log" 2>&1; then
    echo pass > "$RUN/verify-$part.status"
  else
    echo "fail (exit $?)" > "$RUN/verify-$part.status"
    tail -n 40 "$RUN/verify-$part.log" > "$RUN/verify-$part.tail"
  fi
}
if [[ $ANY_CODE -eq 1 ]]; then
  # Codex may have added packages; reinstall from the updated lockfile.
  (cd frontend && npm ci --allow-remote=all --no-audit --no-fund --loglevel=error) >> "$RUN/npm-frontend.log" 2>&1 || true
  NEXT_TELEMETRY_DISABLED=1 verify frontend frontend npx next build
  if [[ -f backend/package.json ]]; then
    (cd backend && npm ci --allow-remote=all --no-audit --no-fund --loglevel=error) >> "$RUN/npm-backend.log" 2>&1 || true
    verify backend backend npm run typecheck
  elif [[ -f backend/pyproject.toml ]]; then
    verify backend backend uv run python -m compileall -q .
  fi
fi

$PY "$BOT_DIR/bin/helper.py" prbody "$UNIT" "$RUN"
rm -rf .doc-sync-bot
log "done (code changes: $ANY_CODE)"
