# Mac 磁盘清理 —— 使用与说明

本文件配套同目录下的 `mac_cleanup.sh`，涵盖两块内容：
- **第一部分 · 自动清理**：脚本能帮我们做什么、怎么用、清哪些、安全策略与报告。
- **第二部分 · 手动清理清单**：**不适合脚本自动删除**的应用级占用，需你在应用内或手动确认后处理。

---

## 第一部分 · 自动清理（`mac_cleanup.sh`）

### 1. 用法

在仓库根目录运行：

```bash
chmod +x tools/cleanup/mac_cleanup.sh

# a) 只查询占用（默认，不删除任何内容）
./tools/cleanup/mac_cleanup.sh

# b) 实际清理（需显式加 --clean）
./tools/cleanup/mac_cleanup.sh --clean

# c) 预览将清理哪些（--clean 配合 --dry-run，不实际删除）
./tools/cleanup/mac_cleanup.sh --clean --dry-run

# h) 帮助
./tools/cleanup/mac_cleanup.sh --help
```

| 模式 | 行为 |
|------|------|
| 默认（无参数） | 仅统计并输出各目录占用，**不删除任何内容** |
| `--clean` | 执行实际清理；涉及 `/tmp`、`/var/folders`、Time Machine 时会提示输入 sudo 密码 |
| `--clean --dry-run` | 只打印将执行的清理命令，不真正删除 |

> 注意：脚本依赖 `bash`（macOS 自带 bash 3.2 即可），并会在部分步骤调用 `sudo`、`find`、`du`、`tmutil`、`npm`/`brew`/`pnpm`/`docker` 等工具（未安装的工具对应步骤自动跳过）。

### 2. 脚本清理了哪些内容

| 步骤 | 清理对象 | 安全策略 |
|------|----------|----------|
| 0（前置） | 磁盘可用空间统计、预取 sudo 权限 | 只读，不删 |
| 1 | `~/Library/Caches` 用户缓存 | 仅删 `mtime +7` 的过期缓存，不误伤正在写入的应用缓存 |
| 2 | `~/Library/Logs` 用户日志 | 仅删 7 天前的旧日志文件，保留目录结构 |
| 3 | `/tmp` 临时目录 | 仅删 1 天前的陈旧临时文件（需 sudo） |
| 4 | `/var/folders` 系统/用户临时缓存容器 | **按当前用户 uid 定向清理**，详见下方专节 |
| 5 | 本地 Time Machine 快照 | 仅在有快照时 `tmutil thinlocalsnapshots` 精简（需 sudo） |
| 6 | `~/.Trash` 废纸篓 | 清空 |
| 7 | 开发者工具缓存 | Xcode DerivedData、npm 缓存（可再生成）；Docker 仅提示 |
| 8 | 大体积高危项目 | ipsw 旧固件、Homebrew 缓存、CocoaPods/Gradle 缓存、Docker `prune -a`、iOS DeviceSupport、旧模拟器；**iOS 设备备份只提示不自动删** |
| 9 | 语言工具链与包管理器缓存 | go / pnpm / npm(`_npx`、`_cacache`) / uv / puppeteer / codex / opencode / golangci-lint / node-gyp / electron 等，均为可再生缓存 |

#### 关于 `/var/folders`（第 4 步）的专门说明

`/var/folders` 里混有**当前用户**和**系统/其它用户**的沙箱数据。脚本的做法：

- 通过 `stat -f '%u'` 找到 **owner uid == 当前登录用户 uid** 的那个容器目录（例如 `/var/folders/_w/<hash>`），**只清这个目录**。
- 系统与其它用户的沙箱目录（`_zz` 下的 `com.apple.WebKit.*`、ScreenTime 等属 root 且受 macOS 保护）会被**自动跳过**，既不误删，也不会刷出大量 `Operation not permitted` 权限噪音。
- 在该用户目录内清理：`T`/`C` 中 7 天以上缓存、`X` 目录的 `code_sign_clone` 代码签名残留与 7 天前旧目录、`T` 下 `go-build*` 编译缓存（`mtime +1`）。

#### 关于 pnpm store

脚本第 9 步采用 `corepack pnpm store prune`（而非裸 `pnpm`），以**绕过 Corepack 的版本切换/联网下载提示**：
裸 `pnpm` 在你的环境里是 Corepack shim，一调用就可能因为项目声明的版本（如 `pnpm@11.21.0`）与缓存不一致而触发「Corepack is about to download … Do you want to continue?」的交互弹窗。改成 `corepack pnpm ...` 后用当前已有版本直接执行，**无感、不弹窗**。

### 3. 安全原则

- **默认只查询**：除非显式加 `--clean`，否则脚本绝不删除。
- **mtime 阈值保护运行中程序**：缓存/日志/临时文件大多数只删「过期（旧于 N 天）」内容，避免误删正在写入/占用的文件。
- **涉及用户数据的高危项只提示**：iOS 设备备份、邮件/短信附件等脚本一律不动，由手动清单处理。
- **Code signing 残留（`X/code_sign_clone`）可安全清**：macOS 会在应用更新时自动重建。

### 4. 清理报告

`--clean` 结束时脚本会输出一份报告：
- 磁盘可用空间前后对比 + **本次实际释放量**（约 X GB）。
- 「实际执行并已确认的清理项」清单。
- 若释放不明显，会提示系统可能延迟记账、建议重启后再看。

查询 / 预览模式会明确标注「未执行任何清理」。

---

## 第二部分 · 手动清理清单（应用内清理）

> 本部分收录**涉及用户数据、不适合脚本自动删除**的应用级占用，需你在应用内或手动确认后清理。所有数值均为本机实测快照，供参考。

### 一、高危 · 含用户数据（务必在应用内清理）

#### 1. 微信（WeChat）—— 约 7.5 G

**数据目录**：`~/Library/Containers/com.tencent.xinWeChat/Data/Documents/`

| 子目录 | 占用 | 说明 |
|--------|------|------|
| `xwechat_files` | 5.7 G | 聊天过程中的图片/视频/文件，**是你的聊天数据** |
| `app_data` | 1.8 G | 应用数据 |

**推荐做法**：在微信「设置 → 通用 → 存储空间」里清理，可选择性删除聊天文件。
- 那里能按「会话」查看各聊天的附件占用，删除后聊天记录里的文件也会消失，请谨慎。

#### 2. 企业微信（WeWork）—— 约 7.6 G

**数据目录**：`~/Library/Containers/com.tencent.WeWorkMac/Data/Documents/`

| 子目录 | 占用 | 说明 |
|--------|------|------|
| `Profiles` | 4.3 G | 聊天文件/表情/图片，**是你的数据** |
| `cefcache` | 3.3 G | 内嵌浏览器缓存（**可安全删除**，退出企业微信后删） |

**推荐做法**：
- `cefcache`：退出企业微信后可直接删除 `cefcache/wew_*` 子目录（纯缓存）。
- `Profiles`：在企业微信内「设置 → 存储空间/清理缓存」操作，勿直接删。

#### 3. OrbStack —— 约 11 G

**数据目录**：`~/Library/Group Containers/HUAQ24HBR6.dev.orbstack/data`

这些是虚拟机/容器的**磁盘镜像**。请在 OrbStack 应用内删除不再使用的 Linux 机器 / Docker 镜像，或对具体 machine 执行 `orb delete <machine>`。不要在 Finder 里直接删 `data` 目录，否则可能损坏正在使用的机器。

#### 4. Microsoft Edge —— 约 9.2 G

**数据目录**：`~/Library/Application Support/Microsoft Edge/`

其中 `Default`（8.7 G）含浏览历史、下载记录、扩展、缓存。

**推荐做法**：Edge「设置 → 隐私/搜索/服务 → 清除浏览数据」，或「设置 → 系统和性能」里管理缓存。想快速释放可清「缓存的图像和文件」。

#### 5. Notion —— 约 4.6 G

**数据目录**：`~/Library/Application Support/Notion/Partitions`

`Partitions` 是本地缓存分区。Notion 目前无直接「清缓存」按钮，可在退出 Notion 后删除 `Partitions` 下的分块缓存（应用会重新同步；账户内容在云端不会丢）。删除前建议先确认已登录并可重新登录。

### 二、中危 · 应用缓存（退出应用后可删，或应用内清理）

| 应用 | 占用 | 位置 / 清理方式 |
|------|------|----------------|
| 网易云音乐 | ~865 M（另含缓存约 800 M） | 应用内「设置 → 清除缓存 / 清除下载」；数据在 `~/Library/Application Support/com.netease.163music` |
| Postman | 1.3 G | `~/Library/Application Support/Postman`（含缓存） |
| bilibili | 514 M | `~/Library/Application Support/bilibili`；应用内设置 → 缓存清理 |
| LarkShell | 1.0 G | `~/Library/Application Support/LarkShell`；应用内设置 → 存储 |
| Xmind | 304 M | 应用内缓存 |
| JetBrains | 818 M | `~/Library/Application Support/JetBrains`；或在各 IDE 内「Invalidate Caches」 |
| GitKrakenCLI / AionUi / Codex 等 | 各 0.1–0.5 G | 多为缓存，可退出后清理对应 `~/Library/Caches` 子项 |

### 三、补充 · 其他常见大头

| 项目 | 说明 |
|------|------|
| iOS 设备备份 | `~/Library/Application Support/MobileSync/Backup`，在 Finder/iTunes「设备」里删除旧备份 |
| 旧 iOS 固件 | `~/Library/iTunes/iPhone Software Updates`，删除旧 `.ipsw` |
| Mail 邮件附件 | `~/Library/Mail`，在「邮件」App 内删除大附件 |
| iMessage 附件 | `~/Library/Messages/Attachments`，按需删除 |
| 系统「可清除空间」 | 「关于本机 → 储存空间 → 管理」，APFS 会在空间不足时自动回收 |
| 睡眠镜像/交换文件 | 重启即可让系统重建 |
| 各浏览器 | Safari/Chrome/Edge 的「清除浏览数据 → 缓存」 |

### 提醒

- 以上「数据目录」路径均含空格，命令行操作时请加引号，例如 `du -sh "~/Library/Application Support/Microsoft Edge"`。
- 涉及聊天/备份/虚拟机磁盘的内容**不可逆**，删除前请务必在应用内二次确认。

---

## 两个部分的分工

| | 自动清理（第一部分） | 手动清理（第二部分） |
|---|---|---|
| 对象 | 缓存 / 日志 / 临时文件 / 工具链 / 系统沙箱残留 | 聊天数据 / 应用文档 / 虚拟机镜像 / 附件 |
| 是否可逆 | 多为可再生缓存，删了能重建 | **不可逆**，需人工确认 |
| 操作方式 | 脚本一键 `--clean` | 应用内或手动 |

一句话：**能自动且安全的，交给 `mac_cleanup.sh`；涉及你数据、需要判断的，按第二部分清单手动处理。**
