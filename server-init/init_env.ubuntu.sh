#!/usr/bin/env bash
set -euo pipefail

# ========================
# 🛠 工具函数
# ========================
log()  { echo "$(date '+%H:%M:%S') ✅ $*"; }
warn() { echo "$(date '+%H:%M:%S') ⚠️  $*"; }
die()  { echo "$(date '+%H:%M:%S') ❌ $*" >&2; exit 1; }

safe_run() { "$@" || warn "命令失败（已跳过）: $*"; }

append_once() {
  # append_once <marker> <line> <file>
  local marker="$1" line="$2" file="$3"
  grep -q "$marker" "$file" 2>/dev/null || echo "$line" >> "$file"
}

echo ""
echo "🚀 Server 初始化开始（运维版 · 可重复执行）..."
echo ""

# ========================
# 🧱 基础环境
# ========================
log "安装基础工具..."
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y \
  git curl wget vim unzip zip \
  ca-certificates gnupg lsb-release software-properties-common \
  net-tools telnet dnsutils \
  htop tree jq make \
  lsof ncdu

# ========================
# 🐳 Docker（官方源）
# ========================
log "配置 Docker 源..."
sudo mkdir -p /etc/apt/keyrings

# --yes 确保重复执行时自动覆盖，不会交互卡住
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --yes --dearmor -o /etc/apt/keyrings/docker.gpg

sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update -y

log "安装 Docker..."
sudo apt-get install -y \
  docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

sudo systemctl enable docker
sudo systemctl start docker

# 幂等：用户已在 docker 组则跳过
if ! groups "$USER" | grep -q '\bdocker\b'; then
  sudo usermod -aG docker "$USER"
  warn "已将 $USER 加入 docker 组，需重新登录后生效"
else
  log "$USER 已在 docker 组，跳过"
fi

# 验证 Docker（用 sudo 避免 newgrp 问题）
if sudo docker run --rm hello-world &>/dev/null; then
  log "Docker 安装验证成功"
else
  warn "Docker hello-world 测试失败，请检查安装"
fi

# ========================
# ⚡ Shell 增强工具
# ========================
log "安装 shell 增强工具..."
sudo apt-get install -y zsh fzf ripgrep

# bat：Ubuntu 20.04 叫 batcat，22.04+ 叫 bat
if sudo apt-get install -y bat 2>/dev/null; then
  log "bat 安装成功"
elif sudo apt-get install -y batcat 2>/dev/null; then
  log "batcat 安装成功"
else
  warn "bat/batcat 安装失败，跳过"
fi

# fd：Ubuntu 20.04 叫 fd-find，22.04+ 叫 fd
if sudo apt-get install -y fd-find 2>/dev/null; then
  log "fd-find 安装成功"
elif sudo apt-get install -y fd 2>/dev/null; then
  log "fd 安装成功"
else
  warn "fd 安装失败，跳过"
fi

# 确保 ~/.local/bin 在 PATH 中
mkdir -p ~/.local/bin
append_once "LOCAL_BIN_PATH" \
  'export PATH="$HOME/.local/bin:$PATH" # LOCAL_BIN_PATH' \
  ~/.bashrc

# bat 软链接（batcat -> bat）
if command -v batcat &>/dev/null && [ ! -f ~/.local/bin/bat ]; then
  ln -sf "$(command -v batcat)" ~/.local/bin/bat
  log "bat 软链接创建成功"
fi

# fd 软链接（fdfind -> fd）
if command -v fdfind &>/dev/null && [ ! -f ~/.local/bin/fd ]; then
  ln -sf "$(command -v fdfind)" ~/.local/bin/fd
  log "fd 软链接创建成功"
fi

# ========================
# 🐚 Oh My Zsh + 插件
# ========================
log "安装 Oh My Zsh..."
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no CHSH=no sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
  log "Oh My Zsh 已存在，跳过"
fi

# 切换默认 shell 为 zsh（幂等）
if [ "$SHELL" != "$(which zsh)" ]; then
  chsh -s "$(which zsh)"
  log "默认 shell 已切换为 zsh，重新登录后生效"
else
  log "默认 shell 已是 zsh，跳过"
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ]; then
  git clone https://github.com/zsh-users/zsh-autosuggestions \
    "${ZSH_CUSTOM}/plugins/zsh-autosuggestions"
else
  log "zsh-autosuggestions 已存在，跳过"
fi

if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" ]; then
  git clone https://github.com/zsh-users/zsh-syntax-highlighting \
    "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting"
else
  log "zsh-syntax-highlighting 已存在，跳过"
fi

# 安全替换 plugins 行（仅当还是默认值时才替换）
if grep -q "^plugins=(git)$" ~/.zshrc 2>/dev/null; then
  sed -i 's/^plugins=(git)$/plugins=(git docker zsh-autosuggestions zsh-syntax-highlighting)/' ~/.zshrc
  log "plugins 配置更新成功"
elif grep -q "zsh-autosuggestions" ~/.zshrc 2>/dev/null; then
  log "plugins 已包含插件配置，跳过"
else
  warn "未找到默认 plugins=(git) 行，请手动更新 ~/.zshrc 中的 plugins"
fi

# alias 写入 zshrc / bashrc（幂等）
for rc in ~/.bashrc ~/.zshrc; do
  [ -f "$rc" ] || continue
  append_once "alias bat=" 'alias bat="$HOME/.local/bin/bat"' "$rc"
  append_once "alias fd="  'alias fd="$HOME/.local/bin/fd"'  "$rc"
done

# ========================
# ☁️  Oh My Zsh 主题：cloud
# ========================
# 使用 Oh My Zsh 内置 cloud 主题，不安装 Starship（两者会冲突）
if grep -q '^ZSH_THEME=' ~/.zshrc 2>/dev/null; then
  sed -i 's/^ZSH_THEME=.*/ZSH_THEME="cloud"/' ~/.zshrc
  log "ZSH_THEME 已设置为 cloud"
else
  append_once 'ZSH_THEME="cloud"' 'ZSH_THEME="cloud"' ~/.zshrc
fi

# 确保没有残留的 starship 初始化（重复执行时清理）
sed -i '/starship init zsh/d' ~/.zshrc 2>/dev/null || true

# ========================
# ⚡ fzf 配置（zsh）
# ========================
FZF_KEY="/usr/share/doc/fzf/examples/key-bindings.zsh"
FZF_CMP="/usr/share/doc/fzf/examples/completion.zsh"
[ -f "$FZF_KEY" ] && append_once "key-bindings.zsh" "source $FZF_KEY" ~/.zshrc
[ -f "$FZF_CMP" ] && append_once "completion.zsh"   "source $FZF_CMP" ~/.zshrc

# ========================
# 🧹 清理
# ========================
sudo apt-get autoremove -y

echo ""
echo "✅ 初始化完成！"
echo ""
echo "⚠️  下一步操作："
echo "  1️⃣  重新登录 或执行: newgrp docker  （使 docker 组生效）"
echo "  2️⃣  切换 zsh:      exec zsh"
echo ""
echo "🎯 已安装能力："
echo "  - Docker / Compose 部署"
echo "  - Git 操作"
echo "  - 网络排查工具（net-tools / dnsutils / telnet）"
echo "  - 高级命令行体验（zsh-autosuggestions + zsh-syntax-highlighting + fzf）"
echo "  - 现代 CLI 工具（bat / fd / ripgrep）"
echo "  - Oh My Zsh cloud 主题"
echo ""