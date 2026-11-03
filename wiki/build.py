#!/usr/bin/env python3
"""Refresh the Markdown indexes and standalone HTML from wiki_data.json."""

from datetime import date, datetime, timezone
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
DATA_FILE = ROOT / "wiki_data.json"
ORDER = ["specs", "core", "tests", "meta"]
CATEGORIES = {
    "specs": ("Specifications", "foundation documents"),
    "core": ("Core", "app and audit engine"),
    "tests": ("Tests", "verification"),
    "meta": ("Meta", "repository workflow"),
}


def dossier(article):
    section = next((item for item in article["sections"]
                    if item.get("heading") == "Dossier"), {})
    return {row[0]: row[1].strip("`") for row in section.get("rows", [])}


def refresh_source_facts(article):
    """Keep dossier line counts and source landmarks tied to the current tree."""
    fields = dossier(article)
    path = fields.get("File")
    source = ROOT.parent / path if path else None
    if source is None or not source.is_file():
        return
    try:
        text = source.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        text = None
    lines = str(len(text.splitlines())) if text is not None else "—"
    for section in article["sections"]:
        if section.get("heading") == "Dossier":
            for row in section["rows"]:
                if row[0] == "Lines":
                    row[1] = lines
        elif section.get("heading") == "Key items" and text is not None:
            if source.suffix == ".md":
                headings = [line.lstrip("# ").strip() for line in text.splitlines()
                            if line.startswith("#")][:12]
                section["rows"] = [[heading, "Section in this project document."]
                                    for heading in headings]
            elif source.suffix == ".swift":
                declarations = []
                pattern = re.compile(
                    r"^(?:(?:public|private|internal|package|fileprivate)\s+)?"
                    r"(?:(?:static|class|final|nonisolated)\s+)*"
                    r"(?:struct|enum|class|protocol|actor|func|typealias)\b"
                )
                for line in text.splitlines():
                    item = line.strip()
                    if pattern.match(item) and item not in declarations:
                        declarations.append(item)
                previous = {row[0]: row[1] for row in section.get("rows", [])}
                section["rows"] = [
                    [item, previous.get(item,
                     f"Declaration in {source.name}; see the article summary for its role.")]
                    for item in declarations[:9]
                ]


def file_articles(data):
    """Keep curated tabs and consolidate file articles into File System."""
    overview = next((tab for tab in data["tabs"] if tab["id"] == "overview"), None)
    if overview is None:
        raise SystemExit("The wiki needs an Overview tab before it can be rebuilt.")

    original_tabs = list(data["tabs"])
    file_system = next((tab for tab in data["tabs"] if tab["id"] == "file-system"), None)
    if file_system is not None:
        entries = file_system.get("files", [])
        file_ids = {entry.get("id") for entry in entries}
        curated_tabs = [tab for tab in original_tabs
                        if tab.get("id") not in {"overview", "file-system"}
                        and tab.get("id") not in file_ids]
    else:
        entries = [tab for tab in data["tabs"]
                   if tab["id"] not in {"overview", "master-index"}]
        curated_tabs = []
        file_system = {
            "id": "file-system",
            "label": "File System",
            "icon": "▦",
            "files": entries,
            "sections": [],
        }

    entries = [entry for entry in entries if entry.get("id") != "master-index"]
    file_system["files"] = entries
    data["tabs"] = [overview, *curated_tabs, file_system]
    return file_system, entries


def file_path(article):
    return dossier(article).get("File", "—")


def file_rows(article):
    fields = dossier(article)
    detail_parts = []
    category = CATEGORIES.get(article.get("category"), (article.get("category", ""), ""))[0]
    if category:
        detail_parts.append(f"Category: {category}")
    for field in ("Language", "Lines", "Status", "Package"):
        if fields.get(field):
            value = fields[field]
            detail_parts.append(f"{field}: {value}" if field == "Lines" else value)
    for field, value in fields.items():
        if field not in {"File", "Language", "Lines", "Status", "Package"} and value:
            detail_parts.append(f"{field}: {value}")

    purpose = next((section.get("body", "") for section in article.get("sections", [])
                    if section.get("heading") == "What it is"), "")
    key_section = next((section for section in article.get("sections", [])
                        if section.get("heading") == "Key items"), {})
    key_items = [" — ".join(str(part) for part in row if part)
                 for row in key_section.get("rows", [])]
    key_text = "; ".join(key_items) if key_items else "—"
    metadata = " · ".join([f"`{file_path(article)}`", *detail_parts])
    return [article.get("label", Path(file_path(article)).name), metadata, purpose, key_text]


def build_file_system_sections(file_system, entries):
    by_directory = {}
    for article in entries:
        path = file_path(article)
        directory = Path(path).parent.as_posix() if path != "—" else "Unknown location"
        by_directory.setdefault(directory, []).append(article)

    sections = [{
        "type": "prose",
        "heading": "Project files",
        "body": (f"{len(entries)} documented files are listed below by folder. "
                 "Each row shows the file path, descriptive metadata, purpose, and key items."),
    }]
    directories = sorted(by_directory, key=lambda value: (value != ".", value.casefold()))
    for directory in directories:
        articles = sorted(by_directory[directory], key=lambda article: file_path(article).casefold())
        heading = "Project root" if directory == "." else directory
        sections.append({
            "type": "table",
            "heading": f"{heading} · {len(articles)} files",
            "columns": ["File", "Path and details", "Purpose", "Key items / sections"],
            "rows": [file_rows(article) for article in articles],
        })
    file_system["sections"] = sections


def main():
    data = json.loads(DATA_FILE.read_text(encoding="utf-8"))
    file_system, articles = file_articles(data)
    for article in articles:
        refresh_source_facts(article)
    groups = {key: [tab for tab in articles if tab.get("category") == key]
              for key in ORDER}
    if sum(map(len, groups.values())) != len(articles):
        raise SystemExit("Every documented file must have a known category.")

    data["meta"]["sources"] = sorted({file_path(article) for article in articles
                                      if file_path(article) != "—"})
    build_file_system_sections(file_system, articles)

    data["meta"]["date"] = date.today().isoformat()
    data["meta"]["generated"] = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    overview = next(tab for tab in data["tabs"] if tab["id"] == "overview")
    for section in overview["sections"]:
        if section.get("heading") == "At a glance":
            values = {row[0]: row for row in section["rows"]}
            file_row = values.get("Files") or values.get("Articles")
            if file_row:
                file_row[0] = "Files"
                file_row[1] = str(len(articles))
            values["Categories"][1] = str(sum(bool(group) for group in groups.values()))
            values["Generated"][1] = data["meta"]["date"]
            if "Re-embed" in values:
                values["Re-embed"][0] = "Rebuild"
                values["Re-embed"][1] = "`python3 wiki/build.py`"
        elif section.get("heading") == "Categories":
            section["rows"] = [
                [CATEGORIES[key][0], str(len(groups[key])), CATEGORIES[key][1]]
                for key in ORDER if groups[key]
            ]

    DATA_FILE.write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n",
                         encoding="utf-8")
    lines = [
        f'# {data["meta"]["title"]} — Wiki Index', "",
        f'> Updated {data["meta"]["date"]} · {len(articles)} documented files · data: `wiki_data.json`',
        "", "## Open the wiki", "", "Open `index.html` in a browser. The page works offline.",
        "", "## Tabs", "",
        "- **Overview** — product scope and operating boundaries.",
        "- **User Guide** — task-based instructions and interactive workflow diagrams.",
        "- **Release Readiness** — release review findings, verification ledger, and functional requirements.",
        "- **File System** — documented project files grouped by folder.",
        "", "## Update the wiki", "",
        "1. Edit `wiki_data.json`, the canonical content file. Guide and overview tabs live in `tabs`; file records live inside the File System tab's `files` list.",
        "2. Keep each file record's `category` set to `specs`, `core`, `tests`, or `meta`.",
        "3. Run `python3 wiki/build.py` from the project root. It refreshes source facts, the File System tables, overview counts, Markdown indexes, and embedded HTML.",
        "", "## Files", ""
    ]
    for key in ORDER:
        group = groups[key]
        if not group:
            continue
        label, subtitle = CATEGORIES[key]
        lines += [f"### {label}", f"*{subtitle}*", "",
                  "| # | file | path | lines | status |",
                  "|---|---------|------|-------|--------|"]
        category_index = [f"# {label}", f"*{subtitle}*", ""]
        rows = []
        for number, article in enumerate(group, 1):
            fields = dossier(article)
            path = fields.get("File", "—")
            count = fields.get("Lines", "—")
            status = fields.get("Status", "")
            lead = next((section.get("body", "") for section in article["sections"]
                         if section.get("heading") == "What it is"), "")
            lead = lead.splitlines()[0].rstrip()[:200].rstrip()
            lines.append(f'| {number:02d} | {article["label"]} | `{path}` | {count} | {status} |')
            rows.append(f'- **{article["label"]}** — `{path}` ({count} lines): {lead}')
        category_index.extend(rows)
        (ROOT / "indexes" / f"{key}.md").write_text("\n".join(category_index) + "\n",
                                                         encoding="utf-8")
        lines.append("")

    (ROOT / "INDEX.md").write_text("\n".join(lines), encoding="utf-8")
    subprocess.run([sys.executable, str(ROOT / "wikiupdate.py")], check=True)
    print(f"Updated {len(articles)} files in the File System tab at {ROOT}")


if __name__ == "__main__":
    main()
