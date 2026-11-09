#!/usr/bin/env bash
# Job 2, step 2: push the unit's commits and open its draft PR. Has GH_TOKEN;
# runs no model-generated commands.
#   open-pr.sh <unit.json>
# Writes $WORK_ROOT/results/<id>/outcome: pr-opened | no-changes | dry-run.
set -euo pipefail
source "$BOT_DIR/bin/lib.sh"

UNIT=$1
read -r ID REPO BASE BRANCH GH_REPO < <($PY -c 'import json,sys; u=json.load(open(sys.argv[1]))
print(u["id"], u["repo"], u["base"], u["branch"], u["ghRepo"])' "$UNIT")
TITLE=$($PY -c 'import json,sys; print(json.load(open(sys.argv[1]))["title"])' "$UNIT")
LOG_TAG=$ID
DIR="$WORK_ROOT/repos/$REPO"
RUN="$WORK_ROOT/results/$ID"

if [[ "$(git -C "$DIR" rev-parse HEAD)" == "$(cat "$RUN/base-sha")" ]]; then
  if grep -qxE 'failed|timeout' "$RUN"/page-*.result 2>/dev/null; then
    log "no commits and Codex failed: leaving this unit for the next run"
    echo failed > "$RUN/outcome"
    exit 1
  fi
  log "no commits: nothing for this unit needed code changes"
  echo no-changes > "$RUN/outcome"
  exit 0
fi
if [[ "${DRY_RUN:-false}" == "true" ]]; then
  log "dry run: not pushing $BRANCH"
  echo dry-run > "$RUN/outcome"
  exit 0
fi

push_branch "$DIR" "$GH_REPO" "$BRANCH"
URL=$(upsert_pr "$GH_REPO" "$BASE" "$BRANCH" "$TITLE" "$RUN/pr-body.md")
echo "$URL" > "$RUN/pr-url"
echo pr-opened > "$RUN/outcome"
log "opened $URL"
