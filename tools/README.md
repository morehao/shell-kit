# Tools

macOS 本地开发环境维护工具脚本集合。

## 目录结构

脚本按类别分目录组织：

| 目录 | 类别 |
|------|------|
| `cleanup/` | 数据清理类工具 |

今后新增脚本时，按其功能放入对应类别目录。

## 脚本列表

| 脚本 | 说明 | 适用系统 |
|------|------|----------|
| `cleanup/cleanup-opencode.sh` | 清理 opencode 数据库旧会话数据并回收空间 | macOS / Linux |

## 清理 opencode 数据（cleanup/cleanup-opencode.sh）

opencode 用事件溯源（event-sourcing）把会话历史写入 SQLite（`~/.local/share/opencode/opencode.db`），
会随使用持续膨胀（常见可达 10G+，其中 `event` 表占大头）。本脚本按保留天数删除 7 天前的旧会话，
并清理孤儿 snapshot，最后 `VACUUM` 回收物理空间。

### 特性

- **按保留天数清理**：默认保留最近 7 天，可自定义天数
- **进程感知**：检测 opencode 是否在运行，默认拒绝执行，避免在活动连接上删库导致损坏
- **安全兜底**：事务内删除、删除前后打印计数、`integrity_check` 校验
- **不触碰鉴权数据**：只动会话相关表，不碰 account/auth/credential

### 用法

```bash
# 默认保留最近 7 天
./cleanup/cleanup-opencode.sh

# 保留最近 30 天
./cleanup/cleanup-opencode.sh 30

# 检测到 opencode 运行时，逐项询问后终止相关进程再清理
./cleanup/cleanup-opencode.sh --kill

# 一键：直接终止（不询问）并按 7 天清理
./cleanup/cleanup-opencode.sh --kill --yes 7
```

### 参数

| 参数 | 说明 |
|------|------|
| `[天数]` | 保留最近 N 天（正整数，默认 7） |
| `--kill` | 检测到 opencode 运行时，列出并询问后终止相关进程 |
| `--yes` | 配合 `--kill`，跳过询问直接终止 |

### 进程检测说明

脚本将 opencode 相关进程分为两类：

- **CLI / serve**：匹配 `opencode-ai/bin/opencode`
- **桌面版**：匹配 `OpenCode.app`

不带 `--kill` 时检测到进程即列出并拒绝执行；带 `--kill` 则先列出，询问确认（或 `--yes` 直接）
终止两类进程后再继续，并做杀后复检，仍有残留则中止。

> ⚠️ 若脚本由运行中的 opencode 会话触发，`--kill` 会终止其宿主进程（即当前会话）。
> 建议：退出所有 opencode 后直接运行；或使用独立终端运行 `--kill`。

### 安全建议

删除不可逆，操作前**务必先备份**：

```bash
# 方式一：整目录 tar 备份（注意压缩大文件可能耗时）
tar -cJf ~/opencode-backup-$(date +%Y%m%d).tar.xz -C ~/.local/share opencode

# 方式二：SQLite 在线备份（对 12G 级大库更快更稳，可对运行中的库执行）
mkdir -p ~/opencode-backup && sqlite3 ~/.local/share/opencode/opencode.db \
  ".backup '$HOME/opencode-backup/opencode.db'"
sqlite3 ~/opencode-backup/opencode.db "PRAGMA integrity_check;"   # 应返回 ok
```

### 效果参考

实测（副本干跑，保留 7 天）：

| 表 | 清理前 | 清理后 |
|----|--------|--------|
| session | 8361 | ~470 |
| message | 190994 | ~19940 |
| part | 778701 | ~81081 |
| event | 1467242 | ~304961 |

数据库体积：约 **12G → 4G**（`integrity_check: ok`，无孤儿数据）。

### 持久化备份说明

- 备份文件默认写在 `$HOME`，建议清理完成后移动到独立存储或移入备份归档
- 若使用定时清理，请确保已存在有效的近期备份
