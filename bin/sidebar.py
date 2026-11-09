"""Fetch a framework's docs sidebar and print it as a flat JSON list.

Usage: python3 -I sidebar.py <docs-root-url> [<prefix>]
       e.g. https://docs.copilotkit.ai/agno            (keeps /agno/... pages)
            https://docs.copilotkit.ai/quickstart /    (built-in agent: unprefixed
                                                        docs, keep the whole tree)

The docs site (Fumadocs) renders only open sidebar folders into HTML, but the
page's RSC response (`RSC: 1` header) carries the whole page tree: separators
(the section headings), folders, and pages with URLs. Output entries:

  {"section": "Generative UI", "folder": "Declarative/Components and surfaces",
   "title": "Surfaces", "url": "/agno/generative-ui/components/surfaces"}

Only pages under the framework's own prefix are kept. Exits non-zero if the
tree can't be found, so a docs-site change fails loudly instead of looking like
"every page was removed".
"""
import json
import re
import sys
import urllib.request
from urllib.parse import urlparse

root = sys.argv[1].rstrip("/")
prefix = (sys.argv[2] if len(sys.argv) > 2 else urlparse(root).path).rstrip("/")

req = urllib.request.Request(root, headers={"RSC": "1", "User-Agent": "doc-sync-bot"})
raw = urllib.request.urlopen(req, timeout=60).read().decode("utf-8", "replace")


def tree_children(obj):
    """Depth-first search for the first list that looks like page-tree nodes."""
    if isinstance(obj, dict):
        kids = obj.get("children")
        if isinstance(kids, list) and any(
            isinstance(k, dict) and k.get("type") in ("separator", "folder", "page")
            for k in kids
        ):
            return kids
        values = obj.values()
    elif isinstance(obj, list):
        values = obj
    else:
        return None
    for value in values:
        found = tree_children(value)
        if found:
            return found
    return None


children = None
for row in re.finditer(r"(?m)^[0-9a-f]+:([\[{].*)$", raw):
    if '"type":"separator"' not in row.group(1):
        continue
    try:
        children = tree_children(json.loads(row.group(1)))
    except ValueError:
        continue
    if children:
        break
if not children:
    sys.exit(f"sidebar tree not found in the RSC payload of {root}")


def label(node, fallback):
    name = node.get("name")
    if isinstance(name, str) and not name.startswith("$"):
        return name
    # Names with icons are React elements; the text is the last string child.
    texts = re.findall(r'"children":"([^"$][^"]*)"', json.dumps(name))
    return texts[-1] if texts else fallback


entries = []
section = "Getting Started"


def walk(nodes, folders):
    global section
    for node in nodes:
        if not isinstance(node, dict):
            continue
        kind = node.get("type")
        if kind == "separator":
            section = label(node, section)
        elif kind == "folder":
            name = label(node, "?")
            index = node.get("index")
            if isinstance(index, dict) and index.get("url"):
                add(index, folders + [name])
            walk(node.get("children", []), folders + [name])
        elif kind == "page" and node.get("url"):
            add(node, folders)


def add(node, folders):
    url = node["url"].rstrip("/") or "/"
    if prefix and not (url == prefix or url.startswith(prefix + "/")):
        return
    entries.append({
        "section": section,
        "folder": "/".join(folders),
        "title": label(node, url.rsplit("/", 1)[-1].replace("-", " ").title()),
        "url": url,
    })


walk(children, [])
seen = set()
unique = [e for e in entries if not (e["url"] in seen or seen.add(e["url"]))]
json.dump(unique, sys.stdout, indent=1)
print()
