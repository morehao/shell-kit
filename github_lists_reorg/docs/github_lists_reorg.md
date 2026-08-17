# GitHub Lists 重组方案

> 将当前 GitHub 用户的 **32 个技术栈型 Lists** 重组为 **19 个产品定位型 Lists**（依据 `github_stars_reclassified.md` 分类清单）。

## 背景与现状

- 当前拥有 **32 个 Lists**（`ai-infra`、`go-lib`、`go-service`、`admin-web` 等，按语言/技术栈命名）。
- 目标分类文件 `~/Downloads/github_stars_reclassified.md` 定义了 **19 个分类**，按**产品定位**划分（`ai-agents`、`developer-tools`、`learning-resources` 等）。
- 三方核对：
  - 实际 star：570 个
  - 分类文件仓库：567 个（去重）
  - 当前 list 内去重仓库：391 个
  - 需直接收集（星了但不在任何旧 list）：179 个

## 核心约束

- **GitHub Lists 数量上限为 32**（实测：`cannot have more than 32 lists`）。当前已满 32，无法直接新建。
- 因此必须**削峰迁移**：新建 1 个前先删除 1 个旧 list，维持总 list 数 ≤ 32。
- 删除旧 list **不会丢失 star**（star 是仓库属性，list 只是分组容器），后续填仓会把这些仓库重新归入新 list。

## 迁移策略（三阶段削峰）

1. **阶段 A — 建全新 list**：对 19 个分类逐个调用 `createUserList`；`list_total() >= 32` 时先用 `deleteUserList` 删一个旧 list 腾位。
2. **阶段 B — 填仓**：对每个新 list，用 `updateUserListsForItem(itemId, listIds=[新list])` 将 `repos + add_only` 全部仓库设入。
   - 该 mutation 为**覆盖式**设置：仓库最终只属于目标新 list。
3. **阶段 C — 删余旧 list**：删除所有剩余旧 list，最终保留恰好 19 个新 list。

## 交付物与脚本

位于 `/Users/morehao/Documents/practice/shell/shell-kit/github_lists_reorg/`：

| 文件 | 作用 |
| --- | --- |
| `scripts/analyze_stars.py` | 只读分析：解析分类文件 → 生成 `migration_plan.json`（新 list → 仓库映射）与 `current_lists.json`（旧 list → id） |
| `scripts/migrate_lists.sh` | 三阶段削峰迁移；`--dry-run` 预览、默认正式执行 |
| `docs/github_lists_reorg.md` | 本方案文档 |

## 执行命令

```bash
# 1. 生成迁移清单（只读）
python3 scripts/analyze_stars.py

# 2. 预览（不写 GitHub）
bash scripts/migrate_lists.sh --dry-run

# 3. 正式执行削峰迁移
bash scripts/migrate_lists.sh
```

## 前置条件

- `gh` 已认证，且 token 需含 **`user` scope**（`createUserList`/`updateUserListsForItem`/`deleteUserList` 均要求）。用 `gh auth refresh --hostname github.com -s user` 补充。
- `python3` 可用。

## 边界仓库处理

- **lists 内但不在分类文件**：`AgentsMesh/AgentsMesh`、`agentclientprotocol/agent-client-protocol`、`kubernetes-sigs/agent-sandbox` → 归入 `ai-agents`。
- **star 了但分类文件缺**：`morehao/go-ark-template` → 归入 `developer-tools`。

## 预期结果

- 迁移后 list 总数 = **19**。
- 19 个分类的仓库条目总数 ≈ **570**（含跨类重复）。
- 所有旧技术栈列表消失，替换为统一的产品定位分类。

## 风险提示

- **不可逆批量操作**，正式执行前请务必先 `--dry-run` 审阅。
- 填仓为覆盖式，若中途失败需检查目标 list 是否已建、仓库 id 是否获取成功。

## 实际执行结果（2026-08-17）

迁移已成功完成，最终校验通过：

- **最终 19 个新 list**，全部仓库数达标：

  | list | 仓库数 | list | 仓库数 |
  | --- | --- | --- | --- |
  | ai-agents | 64 | workflow-automation | 15 |
  | rag-knowledge | 14 | object-storage | 7 |
  | llmops | 6 | networking | 7 |
  | ai-infrastructure | 56 | devops | 15 |
  | authentication | 17 | developer-tools | 127 |
  | api-gateway | 8 | self-hosted | 33 |
  | database | 17 | desktop-apps | 17 |
  | doc-tools | 14 | learning-resources | 82 |
  | web-scraping | 8 | awesome-lists | 37 |
  | admin-dashboard | 26 | | |

- **旧 32 个技术栈 list 已全部删除**。
- **完整性校验**：当前所有 list 内去重仓库 = 570 = 实际 star 数，**零丢失**。

### 执行中的关键坑（后续复用脚本需注意）

1. **list 上限实测为 32**：已满时 `createUserList` 返回 `cannot have more than 32 lists`，必须削峰（先删旧再建新）。
2. **`updateUserListsForItem` 的 `listIds` 必须内联数组写法**：`listIds:["UL_xxx"]`。用 `-f l=[...]` 或 `-F l=[...]` 传参都会被当作字符串 id 解析而报 `Could not resolve to a node with the global id of '["UL_..."]'`。
3. **list 名称大小写不敏感**：旧 list `DevOps` 会阻止新建同名小写 `devops`，需先删除旧的。
4. **网络不稳定导致 EOF**：批量调用可能偶发 `Post ... EOF` 跳过部分仓库，需对比目标数补齐（用差额重填）。

