#!/usr/bin/env python3
"""Render devices/devices.tsv as the Markdown table in devices/README.md (between the markers)."""
import os, re
here = os.path.dirname(os.path.abspath(__file__))
rows = [l.rstrip("\n").split("\t") for l in open(os.path.join(here, "devices.tsv")) if not l.startswith("#")]
order = ["lenovo", "qnap", "synology", "buffalo", "lacie", "zyxel", "plug/nas", "other", "router/appliance", "dev-board"]
rows.sort(key=lambda r: (order.index(r[3]) if r[3] in order else 99, r[2].lower()))
lines = ["| Model | DTB | Family | MCU (LED/fan/power) | Status | Notes |", "| --- | --- | --- | --- | --- | --- |"]
lines += [f"| {r[2]} | `{r[1]}` | {r[3]} | {r[4]} | {r[5]} | {r[6] if len(r) > 6 else ''} |" for r in rows]
readme = os.path.join(here, "README.md")
text = open(readme).read()
new = re.sub(r"(<!-- table:start -->\n).*?(<!-- table:end -->)", lambda m: m.group(1) + "\n".join(lines) + "\n" + m.group(2), text, flags=re.S)
open(readme, "w").write(new)
print(f"{len(rows)} devices")
