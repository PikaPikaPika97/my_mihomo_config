#!/usr/bin/env bash
#
# 在 macOS 上生成并部署 mihomo 配置。
# 流程: generate -> validate -> copy -> restart
#
# 前提:
#   - uv  (用于生成配置): https://docs.astral.sh/uv/#installation
#   - homebrew + mihomo (用于运行): brew install mihomo
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_SOURCE="$REPO_ROOT/official_config.yaml"
MIHOMO_CONFIG="$(brew --prefix)/etc/mihomo/config.yaml"

log()  { printf '\033[1;36m==> %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31m错误: %s\033[0m\n' "$*" >&2; exit 1; }

command -v uv >/dev/null 2>&1 || fail "未找到 uv。请先安装: https://docs.astral.sh/uv/#installation"
command -v brew >/dev/null 2>&1 || fail "未找到 homebrew。请先安装: https://brew.sh"
command -v mihomo >/dev/null 2>&1 || fail "未找到 mihomo。请先安装: brew install mihomo"

# 1. generate
log "生成配置"
uv run --script "$REPO_ROOT/scripts/generate_config.py"

# 2. validate
log "校验配置"
mihomo -t -f "$CONFIG_SOURCE"

# 3. copy (直接覆盖)
log "部署配置到 $MIHOMO_CONFIG"
mkdir -p "$(dirname "$MIHOMO_CONFIG")"
cp "$CONFIG_SOURCE" "$MIHOMO_CONFIG"

# 4. reload/restart
log "通过 brew services 重启 mihomo"
brew services restart mihomo

log "完成"
