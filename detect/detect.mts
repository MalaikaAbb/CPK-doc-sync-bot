/**
 * Runs the repo's own doc-sync (frontend/src/lib/doc-sync/actions.ts) outside
 * Next.js and prints one JSON object describing what moved.
 *
 * Start it with cwd = <repo>/frontend (store.ts derives the repo root from
 * process.cwd()) and a tsconfig mapping `@/*`, `next/cache` and `server-only`.
 * bin/run-detect.sh writes that tsconfig.
 *
 * Side effect: rewrites doc-snapshot/{pages,manifest.json,CHANGELOG.md}
 * exactly as the in-app "Sync docs now" button would.
 */
import { readFile } from "node:fs/promises";
import path from "node:path";

const frontend = process.cwd();
const repoRoot = path.resolve(frontend, "..");

const { runDocSync } = await import(path.join(frontend, "src/lib/doc-sync/actions.ts"));
const { docTargets } = await import(path.join(frontend, "src/lib/doc-sync/paths.ts"));
const { DOCS_ROOT } = await import(path.join(frontend, "src/lib/nav-config.ts"));

const result = await runDocSync();

let report: any = null;
try {
  report = JSON.parse(
    await readFile(path.join(repoRoot, "doc-snapshot/reports/latest.json"), "utf8"),
  );
} catch {}

const changed = (report?.pages ?? []).filter(
  (p: any) => p.outcome === "changed" || p.outcome === "missing",
);

console.log(
  JSON.stringify({
    ok: result.ok,
    baseline: result.baseline,
    message: result.message,
    docsRoot: DOCS_ROOT,
    // Doc pages that already have a harness route.
    covered: docTargets().map((t: any) => t.docPath),
    pages: changed.map((p: any) => ({
      docPath: p.docPath,
      url: p.url.replace(/\.md$/, ""),
      routes: p.routes,
      title: p.title,
      outcome: p.outcome,
      severity: p.severity,
      // Upstream content hash — the key that stops the same change being
      // turned into a PR twice. Missing pages have none.
      sha: p.sha256 ?? `missing:${p.previousSha256 ?? ""}`,
    })),
  }),
);
