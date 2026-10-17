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

# sudo 会重置 PATH；官方 installer 默认把 uv 放在 ~/.local/bin。
UV_BIN=""
UV_RUN_AS_USER=0
if command -v uv >/dev/null 2>&1; then
    UV_BIN="$(command -v uv)"
elif [ -n "${SUDO_USER:-}" ]; then
    user_home="$(dscl . -read "/Users/$SUDO_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')" || true
    if [ -z "$user_home" ]; then
        user_home="/Users/$SUDO_USER"
    fi
    for candidate in "$user_home/.local/bin/uv" "$user_home/.cargo/bin/uv" \
        /opt/homebrew/bin/uv /usr/local/bin/uv; do
        if [ -x "$candidate" ]; then
            UV_BIN="$candidate"
            UV_RUN_AS_USER=1
            break
        fi
    done
fi

if [ -z "$UV_BIN" ]; then
    printf '错误: 未找到 uv。请先安装: https://docs.astral.sh/uv/#installation\n' >&2
    printf '如果在 sudo 下运行，可尝试 sudo -E 或把 uv 加入 root 的 PATH。\n' >&2
    exit 1
fi

run_uv() {
    if [ "$UV_RUN_AS_USER" -eq 1 ]; then
        sudo -u "$SUDO_USER" "$UV_BIN" "$@"
    else
        "$UV_BIN" "$@"
    fi
}

# 先解析 bypass 列表；uv 失败时直接中止，避免静默清空 bypass。
bypass_output="$(run_uv run --script "$RESOLVE" --platform macos)"
set --
while IFS= read -r domain; do
    [ -n "$domain" ] && set -- "$@" "$domain"
done <<< "$bypass_output"

log "开启代理: $NETWORK_SERVICE 127.0.0.1:$PROXY_PORT"
networksetup -setwebproxy "$NETWORK_SERVICE" 127.0.0.1 "$PROXY_PORT"
networksetup -setsecurewebproxy "$NETWORK_SERVICE" 127.0.0.1 "$PROXY_PORT"
networksetup -setwebproxystate "$NETWORK_SERVICE" on
networksetup -setsecurewebproxystate "$NETWORK_SERVICE" on
networksetup -setsocksfirewallproxystate "$NETWORK_SERVICE" off
if [ "$#" -gt 0 ]; then
    networksetup -setproxybypassdomains "$NETWORK_SERVICE" "$@"
else
    # 空列表也要清空旧 bypass，避免沿用上一次的域名。
    networksetup -setproxybypassdomains "$NETWORK_SERVICE" ""
fi

log "代理已开启 ($# 个 bypass 项)"
