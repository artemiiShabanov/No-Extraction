#!/usr/bin/env python3
"""Generate docs/PLAN.md from docs/plan.yaml and, with --github, mirror it to GitHub
as labels, milestones and issues via the gh CLI (idempotent: existing items are skipped).

    python3 tools/github/sync_plan.py            # PLAN.md only
    python3 tools/github/sync_plan.py --github   # also create labels/milestones/issues
    python3 tools/github/sync_plan.py --github --dry-run   # print the gh commands
"""
import json
import os
import subprocess
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
PLAN_YAML = os.path.join(ROOT, "docs", "plan.yaml")
PLAN_MD = os.path.join(ROOT, "docs", "PLAN.md")
SIZE_DAYS = {"S": 0.5, "M": 1.0, "L": 2.0, "XL": 3.0}


def load_yaml(path):
    try:
        import yaml  # type: ignore
    except ImportError:
        sys.exit("PyYAML is required: pip3 install pyyaml")
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f)


def type_label(t):
    return "type: " + t


def owner_label(o):
    return "owner: " + o


def render_md(plan):
    out = ["# План No-Extraction", "",
           "Источник: `docs/plan.yaml`. Обновить этот файл: `python3 tools/github/sync_plan.py`.", "",
           "Размеры: S = полдня, M = день, L = два дня, XL = три дня.", ""]
    total_days = 0.0
    total_open = 0.0
    for ph in plan["phases"]:
        days = sum(SIZE_DAYS[i["size"]] for i in ph["issues"])
        open_days = sum(SIZE_DAYS[i["size"]] for i in ph["issues"] if not i.get("done"))
        total_days += days
        total_open += open_days
        out.append("## %s" % ph["title"])
        out.append("")
        out.append("**Цель:** %s  " % ph["goal"])
        out.append("**Готово, когда:** %s  " % ph["done_when"])
        out.append("**Оценка:** %.1f дн." % days + (" (осталось %.1f)" % open_days if open_days != days else ""))
        out.append("")
        out.append("| | Задача | Тип | Кто | Размер |")
        out.append("|---|---|---|---|---|")
        for i in ph["issues"]:
            mark = "x" if i.get("done") else " "
            out.append("| [%s] | %s | %s | %s | %s |" % (
                mark, i["title"], ", ".join(i["types"]), i["owner"], i["size"]))
        out.append("")
    out.append("## Итого")
    out.append("")
    out.append("Всего %.1f рабочих дней, из них осталось %.1f. Без M6: %.1f." % (
        total_days, total_open,
        total_open - sum(SIZE_DAYS[i["size"]] for ph in plan["phases"] if ph["id"] == "M6" for i in ph["issues"])))
    out.append("")
    out.append("## Метки на GitHub")
    out.append("")
    for group, labels in plan["labels"].items():
        for name, spec in labels.items():
            out.append("- `%s` `#%s` — %s" % (name, spec["color"], spec["desc"]))
    out.append("")
    return "\n".join(out)


def gh(args, dry_run, capture=False):
    cmd = ["gh"] + args
    if dry_run:
        print(" ".join(repr(a) if " " in a else a for a in cmd))
        return ""
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print("  gh failed:", res.stderr.strip())
    return res.stdout if capture else ""


def sync_github(plan, dry_run):
    # labels
    existing = set()
    if not dry_run:
        raw = gh(["label", "list", "--limit", "200", "--json", "name"], dry_run, capture=True)
        existing = {l["name"] for l in json.loads(raw or "[]")}
    for group, labels in plan["labels"].items():
        for name, spec in labels.items():
            if name in existing:
                continue
            gh(["label", "create", name, "--color", spec["color"], "--description", spec["desc"]], dry_run)
    # milestones
    milestones = {}
    if not dry_run:
        raw = gh(["api", "repos/{owner}/{repo}/milestones?state=all&per_page=100"], dry_run, capture=True)
        milestones = {m["title"]: m["number"] for m in json.loads(raw or "[]")}
    for ph in plan["phases"]:
        if ph["title"] in milestones:
            continue
        # always create open: gh can only attach issues to open milestones; done phases are closed below
        gh(["api", "repos/{owner}/{repo}/milestones", "-f", "title=" + ph["title"], "-f", "description=" + ph["goal"]], dry_run)
    # issues
    existing_titles = set()
    if not dry_run:
        raw = gh(["issue", "list", "--state", "all", "--limit", "500", "--json", "title"], dry_run, capture=True)
        existing_titles = {i["title"] for i in json.loads(raw or "[]")}
    for ph in plan["phases"]:
        for i in ph["issues"]:
            if i["title"] in existing_titles:
                continue
            labels = [type_label(t) for t in i["types"]] + [owner_label(i["owner"])]
            body = (i.get("body") or "") + "\n\nРазмер: %s (%.1f дн.)\nФаза: %s" % (i["size"], SIZE_DAYS[i["size"]], ph["title"])
            args = ["issue", "create", "--title", i["title"], "--body", body, "--milestone", ph["title"]]
            for l in labels:
                args += ["--label", l]
            out = gh(args, dry_run, capture=True)
            if i.get("done") and out.strip():
                gh(["issue", "close", out.strip().rsplit("/", 1)[-1]], dry_run)
    # close milestones of finished phases (after their issues exist)
    if not dry_run:
        raw = gh(["api", "repos/{owner}/{repo}/milestones?state=all&per_page=100"], dry_run, capture=True)
        milestones = {m["title"]: m for m in json.loads(raw or "[]")}
    for ph in plan["phases"]:
        m = milestones.get(ph["title"]) if not dry_run else None
        if ph.get("status") == "done" and (dry_run or (m and m["state"] == "open")):
            num = str(m["number"]) if m else "<number>"
            gh(["api", "-X", "PATCH", "repos/{owner}/{repo}/milestones/" + num, "-f", "state=closed"], dry_run)


def main():
    plan = load_yaml(PLAN_YAML)
    with open(PLAN_MD, "w", encoding="utf-8") as f:
        f.write(render_md(plan))
    print("wrote", os.path.relpath(PLAN_MD, ROOT))
    if "--github" in sys.argv:
        sync_github(plan, "--dry-run" in sys.argv)


if __name__ == "__main__":
    main()
