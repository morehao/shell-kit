#!/usr/bin/env bash
#
# migrate_lists.sh — 将 GitHub Lists 重组为新分类清单（削峰迁移，幂等可恢复）
#
# 用法:
#   bash migrate_lists.sh --dry-run        # 预览: 只打印将执行操作, 不写 GitHub
#   bash migrate_lists.sh                  # 正式执行: 建list -> 填仓 -> 删旧list
#   bash migrate_lists.sh --plan <file>    # 指定迁移清单(默认 migration_plan.json)
#   bash migrate_lists.sh --keep <names>   # 逗号分隔, 删除旧list时保留这些名字(如已复用的)
#
# 背景:
#   GitHub 对每个用户可创建的 lists 有上限(实测 32)。因此需"削峰"迁移。
#   本脚本幂等: 已存在的同名新 list 会被复用, 不会重复创建。
#
# 三阶段:
#   阶段A 建全新 list : 已存在则跳过; 需要创建且总数>=32时先删一个旧list腾位
#   阶段B 填仓        : 把清单内每个仓库 updateUserListsForItem 设入对应新 list
#   阶段C 删旧 list   : 删除当前仍存在、且不属于新分类清单的旧 list
#
# 说明:
#   - 删除旧 list 只会让仓库脱离"旧分组", 不影响其 star; 阶段B 会把这些仓库重新归入新 list。
#   - updateUserListsForItem 为覆盖式(listIds 全量设置), 需内联数组写法: listIds:["id"]。
#   - 危险: 不可逆批量写。正式执行前务必 --dry-run 审阅。
#   - 依赖: gh 已认证且具有 user scope; python3。
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PLAN="$ROOT_DIR/migration_plan.json"
DRY_RUN=0
KEEP_NAMES=""
NO_DELETE=0

for arg in "$@"; do
  case "$arg" in
    --dry-run)    DRY_RUN=1 ;;
    --no-delete)  NO_DELETE=1 ;;
    --plan=*)     PLAN="${arg#*=}" ;;
    --keep=*)     KEEP_NAMES="${arg#*=}" ;;
    -h|--help)    sed -n '1,40p' "$0"; exit 0 ;;
    *) echo "未知参数: $arg" >&2; exit 1 ;;
  esac
done

[[ -f "$PLAN" ]] || { echo "错误: 缺少迁移清单 $PLAN (先跑 analyze_stars.py)" >&2; exit 1; }

echo "=================================================="
echo "  GitHub Lists 削峰迁移 (幂等)"
echo "  计划: $PLAN"
echo "  模式: $([[ "$DRY_RUN" == 1 ]] && echo 'DRY-RUN(仅预览)' || echo '正式执行')"
echo "=================================================="

PLAN="$PLAN" DRY="$DRY_RUN" KEEP="$KEEP_NAMES" NODEL="$NO_DELETE" python3 - <<'PYEOF'
import json, os, subprocess, sys, time

PLAN = os.environ["PLAN"]
DRY = os.environ["DRY"] == "1"
KEEP = set(x for x in os.environ["KEEP"].split(",") if x)
NODEL = os.environ["NODEL"] == "1"
LIMIT = 32

def gh_run(args):
    """执行 gh api graphql, 返回 stdout 字符串。失败返回 None。"""
    p = subprocess.run(["gh", "api", "graphql"] + args, capture_output=True, text=True)
    if p.returncode != 0:
        sys.stderr.write(f"gh 失败: {p.stderr.strip()}\n")
        return None
    return p.stdout.strip()

def total():
    r = gh_run(["-f", "query=query{viewer{lists{totalCount}}}",
                "--jq", ".data.viewer.lists.totalCount"])
    return int(r) if r else -1

def all_lists():
    txt = gh_run(["-f", "query=query{viewer{lists(first:100){nodes{name id}}}}",
                  "--jq", '.data.viewer.lists.nodes[] | "\(.name)|\(.id)"'])
    out = []
    if txt:
        for line in txt.splitlines():
            if "|" in line:
                n, i = line.split("|", 1)
                out.append((n, i))
    return out

def create_list(name):
    return gh_run([
        "-f", f"query=mutation($n:String!){{createUserList(input:{{name:$n}}){{list{{id}}}}}}",
        "-f", f"n={name}", "--jq", ".data.createUserList.list.id"]) or ""

def delete_list(lid):
    return gh_run([
        "-f", f"query=mutation($i:ID!){{deleteUserList(input:{{listId:$i}}){{clientMutationId}}}}",
        "-f", f"i={lid}", "--jq", ".data.deleteUserList.clientMutationId"])

def repo_id(full):
    owner, name = full.split("/", 1)
    return gh_run([
        "-f", f"query={{repository(owner:\"{owner}\",name:\"{name}\"){{id}}}}",
        "--jq", ".data.repository.id"]) or ""

def add_to_list(rid, lid):
    """内联数组写法设置 listIds。成功返回 True。"""
    r = gh_run([
        "-f", f"query=mutation($i:ID!){{updateUserListsForItem(input:{{itemId:$i,listIds:[\"{lid}\"]}}){{clientMutationId}}}}",
        "-f", f"i={rid}", "--jq", ".data.updateUserListsForItem.clientMutationId"])
    return r is not None

data = json.load(open(PLAN))
tasks = data["lists"]

# 新分类名集合
new_names = set(t["name"] for t in tasks)

# ---------- 阶段 A: 确保 19 个新 list 存在 ----------
print("\n[阶段A] 确保新 list 存在 (上限=%d, 当前总数=%d)" % (LIMIT, total()))
existing = {n: i for n, i in all_lists()}
ready = {}     # 新分类名 -> lid
for t in tasks:
    name = t["name"]
    if name in existing:
        ready[name] = existing[name]
        print(f"  复用 '{name}' -> {existing[name]}")
        continue
    if DRY:
        ready[name] = f"(new:{name})"
        print(f"  [dry] create '{name}'")
        continue
    # 腾位
    if total() >= LIMIT:
        # 找一个可删的旧 list (不在新分类名里的)
        victim = None
        for n, i in all_lists():
            if n not in new_names and n not in KEEP:
                victim = i
                break
        if victim:
            delete_list(victim)
            print(f"  删旧腾位 {victim}")
    lid = create_list(name)
    if lid:
        ready[name] = lid
        existing[name] = lid
        print(f"  创建 '{name}' -> {lid}")
    time.sleep(0.2)

print(f"  新 list 就绪: {len(ready)} 个  当前总数={total()}")

# ---------- 阶段 B: 填仓 ----------
print("\n[阶段B] 填仓全部仓库到新 list")
total_added = 0
for t in tasks:
    name = t["name"]
    lid = ready.get(name)
    if not lid:
        print(f"  跳过 '{name}' (list 未就绪)", file=sys.stderr)
        continue
    repos = sorted(set(t.get("repos", [])) | set(t.get("add_only", [])))
    if DRY:
        print(f"  [dry] fill '{name}' -> {len(repos)} 仓库")
        total_added += len(repos)
        continue
    ok = 0
    for r in repos:
        rid = repo_id(r)
        if not rid:
            print(f"    !! 跳过 {r}: 无 repository id", file=sys.stderr)
            continue
        if add_to_list(rid, lid):
            ok += 1
        time.sleep(0.03)
    total_added += ok
    print(f"  -> '{name}' 填仓完成: {ok}/{len(repos)}")
print(f"  填仓仓库条目: {total_added}" + ("[dry: 应写入数]" if DRY else ""))

# ---------- 阶段 C: 删剩余旧 list ----------
if NODEL:
    print("\n[阶段C] --no-delete, 跳过旧 list 删除")
else:
    print("\n[阶段C] 删除剩余旧 list")
    if DRY:
        old_left = [(n, i) for n, i in all_lists() if n not in new_names and n not in KEEP]
        print(f"  [dry] 将删除旧 list: {len(old_left)} 个 -> {[n for n, _ in old_left]}")
    else:
        removed = 0
        for n, i in all_lists():
            if n in new_names or n in KEEP:
                continue
            if delete_list(i):
                removed += 1
                print(f"  删除旧 list: {n}")
            else:
                print(f"  !! 删除失败: {n}", file=sys.stderr)
            time.sleep(0.1)
        print(f"  删除旧 list: {removed} 个")
        print(f"  最终 list 总数: {total()}")
PYEOF

echo ""
echo ">>> 迁移流程完成。"
