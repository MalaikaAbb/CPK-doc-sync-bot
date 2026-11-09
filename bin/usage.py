"""Sum token usage from one or more `codex exec --json` event logs.

Usage: python3 -I usage.py <events.jsonl>...
Prints one line: "input N (cached M) · output K". Codex reports usage on its
`turn.completed` events; anything else is ignored.
"""
import json
import sys

totals = {"input_tokens": 0, "cached_input_tokens": 0, "output_tokens": 0}
seen = False
for path in sys.argv[1:]:
    try:
        lines = open(path, encoding="utf-8", errors="replace")
    except OSError:
        continue
    for line in lines:
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if not isinstance(event, dict) or event.get("type") != "turn.completed":
            continue
        usage = event.get("usage") or {}
        for key in totals:
            value = usage.get(key)
            if isinstance(value, int):
                totals[key] += value
                seen = True

if not seen:
    print("not reported")
else:
    print(
        f"input {totals['input_tokens']:,} (cached {totals['cached_input_tokens']:,})"
        f" · output {totals['output_tokens']:,}"
    )
