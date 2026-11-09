# Shared helpers for the doc-sync scripts. Source it; don't run it.
# Expects BOT_DIR and WORK_ROOT to be set (the workflow sets both).

PY="python3 -I"
log() { printf '%s [%s] %s\n' "$(date -u +%T)" "${LOG_TAG:-doc-sync}" "$*"; }

# clone_repo <remote> <base> <dir>
# Clones with GH_TOKEN when one is set (private repos), then strips the token
# from the remote so nothing later in the job can read it out of .git/config.
clone_repo() {
  local remote=$1 base=$2 dir=$3 url=$1
  if [[ -n "${GH_TOKEN:-}" && "$remote" == https://github.com/* ]]; then
    url="https://x-access-token:${GH_TOKEN}@${remote#https://}"
  fi
  rm -rf "$dir"
  git clone --quiet --depth 1 --branch "$base" "$url" "$dir"
  git -C "$dir" remote set-url origin "$remote"
  git -C "$dir" config user.name  "doc-sync-bot"
  git -C "$dir" config user.email "doc-sync-bot@users.noreply.github.com"
  echo '.doc-sync-bot/' >> "$dir/.git/info/exclude"
}

# run_doc_sync <repo-dir> <out.json>
# The repo's own doc-sync, run outside Next: `@/*` → frontend/src, and the two
# Next-only imports replaced by no-op shims. Needs no npm install in the repo.
run_doc_sync() {
  local dir=$1 out=$2 tsconfig
  tsconfig=$(mktemp --suffix=.json)
  cat > "$tsconfig" <<EOF
{ "compilerOptions": { "module": "esnext", "moduleResolution": "bundler", "target": "es2022",
  "allowJs": true, "jsx": "react-jsx",
  "paths": { "@/*": ["$dir/frontend/src/*"],
             "next/cache": ["$BOT_DIR/detect/shims/next-cache.ts"],
             "server-only": ["$BOT_DIR/detect/shims/server-only.ts"] } } }
EOF
  (cd "$dir/frontend" && "$BOT_DIR/detect/node_modules/.bin/tsx" --tsconfig "$tsconfig" \
     "$BOT_DIR/detect/detect.mts") > "$out"
}

# agents_md <name> — shared rules plus the repo's own notes, if it has any.
agents_md() {
  cat "$BOT_DIR/agents-md/common.md"
  [[ -f "$BOT_DIR/agents-md/$1.md" ]] && cat "$BOT_DIR/agents-md/$1.md"
  return 0
}

# pr_state <gh-repo> <branch> → open | merged | closed | none
pr_state() {
  gh pr list --repo "$1" --head "$2" --state all --limit 1 \
    --json state --jq '.[0].state // "none" | ascii_downcase'
}

# push_branch <dir> <gh-repo> <branch>
push_branch() {
  git -C "$1" push --quiet --force \
    "https://x-access-token:${GH_TOKEN}@github.com/$2.git" "HEAD:refs/heads/$3"
}

# upsert_pr <gh-repo> <base> <branch> <title> <body-file>  → prints the PR URL
upsert_pr() {
  local url
  url=$(gh pr list --repo "$1" --head "$3" --state open --json url --jq '.[0].url // ""')
  if [[ -n "$url" ]]; then
    gh pr edit "$url" --title "$4" --body-file "$5" >/dev/null
  else
    url=$(gh pr create --repo "$1" --base "$2" --head "$3" --draft \
            --title "$4" --body-file "$5")
  fi
  echo "$url"
}
