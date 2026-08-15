#!/usr/bin/env bash
#
# 在 macOS 上开启系统代理并写入 bypass 列表。
# 需要 sudo 执行: sudo bash scripts/macos/proxy_on.sh
#
# 环境变量（可选）:
#   NETWORK_SERVICE  网络服务名，默认 Wi-Fi
#   PROXY_PORT       本地代理端口，默认 7890
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVE="$SCRIPT_DIR/../resolve_proxy_bypass.py"

NETWORK_SERVICE="${NETWORK_SERVICE:-Wi-Fi}"
PROXY_PORT="${PROXY_PORT:-7890}"

log() { printf '\033[1;36m==> %s\033[0m\n' "$*"; }

command -v uv >/dev/null 2>&1 || {
    printf '错误: 未找到 uv。请先安装: https://docs.astral.sh/uv/#installation\n' >&2
    exit 1
}

# 先解析 bypass 列表；uv 失败时直接中止，避免静默清空 bypass。
bypass_output="$(uv run --script "$RESOLVE" --platform macos)"
bypass_domains=()
while IFS= read -r domain; do
    [[ -n "$domain" ]] && bypass_domains+=("$domain")
done <<< "$bypass_output"

log "开启代理: $NETWORK_SERVICE 127.0.0.1:$PROXY_PORT"
networksetup -setwebproxy "$NETWORK_SERVICE" 127.0.0.1 "$PROXY_PORT"
networksetup -setsecurewebproxy "$NETWORK_SERVICE" 127.0.0.1 "$PROXY_PORT"
networksetup -setsocksfirewallproxystate "$NETWORK_SERVICE" off
networksetup -setproxybypassdomains "$NETWORK_SERVICE" "${bypass_domains[@]}"

log "代理已开启 (${#bypass_domains[@]} 个 bypass 项)"
