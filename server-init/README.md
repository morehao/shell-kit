# Server Init

服务器环境初始化脚本集合。

## 脚本列表

| 脚本 | 说明 | 适用系统 |
|------|------|----------|
| `init_env.ubuntu.sh` | 基础环境 + Docker + Oh My Zsh 初始化 | Ubuntu / Debian |

## 使用方法

```bash
cd server-init
chmod +x init_env.ubuntu.sh
./init_env.ubuntu.sh
```

## 已安装能力

- Docker / Docker Compose
- Git、curl、wget、vim 等基础工具
- 网络排查工具（net-tools、telnet、dnsutils）
- zsh + Oh My Zsh + 插件（zsh-autosuggestions、zsh-syntax-highlighting）
- 现代 CLI 工具（bat、fd、fzf、ripgrep）