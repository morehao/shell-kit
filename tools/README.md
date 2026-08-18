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
| `cleanup/mac_cleanup.sh` | 清理缓存/日志/临时文件/Time Machine 快照/大体积开发缓存等，支持 `--dry-run` 预览 | macOS |
| `cleanup/manual_cleanup.md` | 手动清理清单（微信/企业微信/OrbStack/浏览器等含用户数据的应用内清理指引） | macOS |

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

## 清理 Mac 磁盘空间（cleanup/mac_cleanup.sh）

macOS 磁盘空间清理脚本，覆盖缓存、日志、临时文件、Time Machine 本地快照、废纸篓、开发者缓存，
以及通常占空间最大的大体积项目。

### 特性

- **`--dry-run` 预览**：默认先看再删，不实际删除任何内容
- **按过期时间过滤**：缓存/日志/临时文件只清理 `-mtime` 过期的内容，不误伤运行中进程正在使用的文件
- **数据类仅提示不删**：iOS 设备备份属用户数据，只显示大小与路径，不自动删除
- **大小检测**：每项清理前先打印当前占用，便于对比收益

### 用法

> 以下命令在仓库根目录运行。

```bash
chmod +x tools/cleanup/mac_cleanup.sh

# 先预览将清理什么（不删除）
./tools/cleanup/mac_cleanup.sh --dry-run

# 确认后实际清理
./tools/cleanup/mac_cleanup.sh
```

### 清理项目

| 步骤 | 项目 | 处理 |
|------|------|------|
| 1 | 用户缓存 `~/Library/Caches` | 删 1 天前未改动内容 |
| 2 | 用户日志 `~/Library/Logs` | 删 7 天前旧日志 |
| 3 | `/tmp` 临时目录 | 删 1 天前内容 |
| 4 | `/var/folders` 临时/缓存容器 | 删 7 天前过期缓存 |
| 5 | Time Machine 本地快照 | `tmutil thinlocalsnapshots` |
| 6 | 废纸篓 `~/.Trash` | 清空 |
| 7 | 开发者缓存（Xcode DerivedData、npm） | 删除 |
| 8 | 大体积项目（见下表） | 见下 |
| 9 | 语言工具链/包管理器缓存（安全可再生） | 见下 |

**第 8 步 大体积项目：**

| 项目 | 处理 |
|------|------|
| iOS 设备备份 | 仅提示大小与路径，不自动删除 |
| 旧 iOS 固件 (ipsw) | 自动删除 |
| Homebrew 缓存 | `brew cleanup --prune=all` |
| CocoaPods 缓存 | 自动删除 |
| Gradle 缓存 | 自动删除 |
| Docker | `docker system prune -a --force` |
| Xcode iOS DeviceSupport | 自动删除 |
| 不可用旧模拟器 | `xcrun simctl delete unavailable` |

**第 9 步 安全可再生缓存（语言工具链/包管理器）：**

| 项目 | 处理 |
|------|------|
| Go 缓存（go-build / goimports / gopls / golangci-lint） | 自动删除 |
| pnpm store | `pnpm store prune`（只回收未引用包） |
| npm cache / npx 历史安装 | `npm cache clean --force` |
| uv / puppeteer / node / codex / opencode 缓存 | 自动删除 |
| ms-playwright / pip / node-gyp / electron 缓存 | 自动删除 |

### 安全说明

- 涉及 `sudo` 的步骤（`/tmp`、`/var/folders`、Time Machine）会在开头 `sudo -v` 预取权限，失败会明确告警并跳过。
- 除 iOS 备份外，其余删除项均为**可再生缓存/构建产物**，删除后下次会自动重建或重新下载。
- 请在首次运行时先用 `--dry-run` 预览，确认无误后再实际执行。
- 涉及用户数据的应用（微信/企业微信/OrbStack/浏览器等）**不自动删除**，请参考 [`cleanup/manual_cleanup.md`](./cleanup/manual_cleanup.md) 在应用内手动清理。
