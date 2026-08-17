#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# analyze_stars.py — 解析分类清单文件，生成 Lists 重组迁移清单（dry-run，只读）
#
# 用法:
#   python3 analyze_stars.py                                   # 读取默认文件，输出迁移清单
#   python3 analyze_stars.py --input <分类文件.md>             # 指定分类清单文件
#   python3 analyze_stars.py --dump <json>                     # 读取已抓取的旧 list 快照
#   python3 analyze_stars.py --orphan ai-agents                # 将文件外孤儿仓库派到该分类
#
# 说明:
#   - 完全不写 GitHub，只做分析并生成 <dir>/migration_plan.json
#   - 解析 <分类文件.md> 中的 "## <分类>" 段落及其下 "github.com/owner/repo"
#   - 比对: 实际 star / 文件内仓库 / 当前 list 内仓库
#   - 输出新增 list 清单、需收集的仓库、孤儿仓库建议
#
import argparse
import json
import os
import re
import subprocess
import sys

DEFAULT_INPUT = "/Users/morehao/Downloads/github_stars_reclassified.md"
WORK_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_PLAN = os.path.join(WORK_ROOT, "migration_plan.json")

GITHUB_RE = re.compile(r"github\.com/([^/\s()]+/[^/\s()]+)")


def run_gh(args):
    """调用 gh，返回解析后的输出。"""
    p = subprocess.run(["gh"] + args, capture_output=True, text=True)
    if p.returncode != 0:
        sys.stderr.write("gh 失败: %s\n%s\n" % (" ".join(args), p.stderr))
        sys.exit(1)
    return json.loads(p.stdout)


def fetch_my_stars():
    """拉取当前用户全部 star 的 full_name 集合。"""
    p = subprocess.run(
        ["gh", "api", "-X", "GET", "user/starred", "--paginate", "--jq", ".[].full_name"],
        capture_output=True, text=True,
    )
    if p.returncode != 0:
        sys.stderr.write("拉取 star 失败: %s\n" % p.stderr)
        sys.exit(1)
    return set(p.stdout.split())


def parse_classify_file(path):
    """解析分类清单 markdown → {分类名: [full_name,...]}"""
    cats = {}
    cur = None
    with open(path, encoding="utf-8") as f:
        for line in f:
            m = re.match(r"^##\s+(\S+)", line.strip())
            if m:
                cur = m.group(1)
                if cur == "分类统计":
                    cur = None
                    continue
                cats[cur] = []
                continue
            if cur:
                mm = GITHUB_RE.search(line)
                if mm:
                    cats[cur].append(mm.group(1))
                elif line.strip().startswith("|") and "仓库" in line:
                    pass
                elif line.strip().startswith("##"):
                    cur = None
    return cats


def fetch_current_lists():
    """拉取当前全部 list 及内部仓库（去重）→ {slug: [full_name,...]}"""
    lists = run_gh([
        "api", "graphql", "-f",
        "query=query { viewer { lists(first:100) { nodes { id slug } } } }",
    ])["data"]["viewer"]["lists"]["nodes"]

    result = {}
    for lst in lists:
        items = []
        cursor = None
        while True:
            base = ("query=query($id:ID!){ node(id:$id){ ... on UserList { "
                    "items(first:100){ pageInfo{hasNextPage endCursor} "
                    "nodes{ ... on Repository { nameWithOwner } } } } } }")
            with_cur = ("query=query($id:ID!,$c:String!){ node(id:$id){ ... on UserList { "
                        "items(first:100, after:$c){ pageInfo{hasNextPage endCursor} "
                        "nodes{ ... on Repository { nameWithOwner } } } } } }")
            args = ["api", "graphql", "-f"]
            if cursor:
                args += [with_cur, "-f", "id=%s" % lst["id"], "-f", "c=%s" % cursor]
            else:
                args += [base, "-f", "id=%s" % lst["id"]]
            r = run_gh(args)
            page = r["data"]["node"]["items"]
            items.extend(it["nameWithOwner"] for it in page["nodes"])
            if not page["pageInfo"]["hasNextPage"]:
                break
            cursor = page["pageInfo"]["endCursor"]
            if not cursor:
                break
        result[lst["slug"]] = {"id": lst["id"], "repos": items}
    return result


def main():
    ap = argparse.ArgumentParser(description="解析分类清单，生成 Lists 重组迁移清单（只读）")
    ap.add_argument("--input", default=DEFAULT_INPUT, help="分类清单文件路径")
    ap.add_argument("--orphan", default="ai-agents",
                    help="清单外孤儿仓库派入的分类名，默认 ai-agents")
    args = ap.parse_args()

    print("=" * 60)
    print("  GitHub Lists 重组分析 (dry-run, 只读)")
    print("  分类清单: %s" % args.input)
    print("=" * 60)

    cats = parse_classify_file(args.input)
    file_repos = set(r for rs in cats.values() for r in rs)
    print("\n分类数: %d" % len(cats))
    print("文件内仓库(去重): %d" % len(file_repos))

    print("\n[1/4] 拉取当前实际 star ...")
    my_stars = fetch_my_stars()
    print("  实际 star 数: %d" % len(my_stars))

    print("[2/4] 拉取当前 lists ...")
    cur_lists = fetch_current_lists()
    print("  当前 list 数: %d" % len(cur_lists))
    cur_repos = set(r for v in cur_lists.values() for r in v["repos"])
    print("  当前 list 内去重仓库: %d" % len(cur_repos))

    # 孤儿 / 差异
    in_file_not_cur = file_repos - cur_repos      # 需直接加入(星了但在任何list)
    in_cur_not_file = cur_repos - file_repos       # 旧list里有但文件外
    not_my = file_repos - my_stars                  # 文件里有但我没star
    my_not_file = my_stars - file_repos             # 我star了但文件缺

    print("\n[3/4] 差异分析:")
    print("  需直接加入(文件有但当前list没有): %d" % len(in_file_not_cur))
    print("  旧list有但清单外(孤儿):         %d -> 派入 [%s]" % (
        len(in_cur_not_file), args.orphan))
    for r in sorted(in_cur_not_file):
        print("      " + r)
    print("  文件有但未star(忽略):             %d" % len(not_my))
    print("  star了但文件缺(未归类):           %d" % len(my_not_file))
    for r in sorted(my_not_file):
        print("      " + r)

    # 组装迁移计划: 每个新分类 -> 仓库列表
    plan = []
    for cat, repos in cats.items():
        repo_set = set(repos)
        task = {
            "name": cat,
            "repos": sorted(repo_set & my_stars),
            "add_only": sorted((repo_set - cur_repos) & my_stars),
        }
        plan.append(task)
    # 孤儿仓库并入指定分类(而非新建重复 list)
    if in_cur_not_file:
        orph_task = next((t for t in plan if t["name"] == args.orphan), None)
        if orph_task is not None:
            orph_task["add_only"] = sorted(set(orph_task["add_only"]) | in_cur_not_file)
            orph_task["flags"] = list(set(orph_task.get("flags", [])) | {"+orphan"})
        else:
            plan.append({
                "name": args.orphan,
                "repos": [],
                "add_only": sorted(in_cur_not_file),
                "flags": ["+orphan"],
            })

    # star 了但分类文件缺、且不在任何旧 list 的仓库(my_not_file 中不属于当前 list 的)
    # 归入 developer-tools, 避免迁移后脱离所有 list
    dev_task = next((t for t in plan if t["name"] == "developer-tools"), None)
    leftover = (my_not_file - in_cur_not_file) if dev_task else set()
    if leftover:
        dev_task["add_only"] = sorted(set(dev_task["add_only"]) | leftover)
        dev_task["flags"] = list(set(dev_task.get("flags", [])) | {"+leftover"})

    with open(OUT_PLAN, "w", encoding="utf-8") as f:
        json.dump({"lists": plan}, f, ensure_ascii=False, indent=1)

    # 输出当前旧 list 结构供 --delete-old 阶段使用
    cur_slug_id = {slug: v["id"] for slug, v in cur_lists.items()}
    with open(os.path.join(WORK_ROOT, "current_lists.json"), "w", encoding="utf-8") as f:
        json.dump(cur_slug_id, f, ensure_ascii=False, indent=1)

    total_new_repos = sum(len(t["repos"]) for t in plan)
    total_add = sum(len(t["add_only"]) for t in plan)
    print("\n[4/4] 生成迁移清单 -> %s" % OUT_PLAN)
    print("  规划新 list 数: %d" % len(plan))
    print("  规划总仓库条目(含重复): %d" % total_new_repos)
    print("  其中需新增收集: %d" % total_add)
    print("\n按分类规模:")
    for t in sorted(plan, key=lambda x: -len(x["repos"])):
        tag = " [" + " ".join(t.get("flags", [])) + "]" if t.get("flags") else ""
        print("  %-22s %4d  (需新增 %d)%s" % (
            t["name"], len(t["repos"]), len(t["add_only"]), tag))


if __name__ == "__main__":
    main()
