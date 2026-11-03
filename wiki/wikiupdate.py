#!/usr/bin/env python3
"""Re-embed wiki_data.json into index.html (HaulCore wiki maintenance pattern).

Edit wiki_data.json first, then:  python3 wikiupdate.py
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "wiki_data.json")
TEMPLATE = os.path.join(HERE, "template.html")
PAGE = os.path.join(HERE, "index.html")

with open(DATA, encoding="utf-8") as f:
    payload = json.load(f)
raw = json.dumps(payload, indent=1, ensure_ascii=False).replace("</", "<\\/")
with open(TEMPLATE, encoding="utf-8") as f:
    page = f.read()
if page.count("__WIKI_DATA__") != 1:
    raise SystemExit("wiki/template.html must contain exactly one __WIKI_DATA__ marker")
page = page.replace("__WIKI_DATA__", raw)
with open(PAGE, "w", encoding="utf-8") as f:
    f.write(page)
print("built", PAGE, "from", TEMPLATE, "and", DATA)
