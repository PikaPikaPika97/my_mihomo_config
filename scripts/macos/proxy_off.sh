#!/usr/bin/env bash
#
# 关闭 macOS 系统代理。只关闭 HTTP/HTTPS/SOCKS 代理状态，不清空 bypass，
# 避免破坏公司原有的 bypass 配置。
# 需要 sudo 执行: sudo bash scripts/macos/proxy_off.sh
#
# 环境变量（可选）:
#   NETWORK_SERVICE  网络服务名，默认 Wi-Fi
set -euo pipefail

NETWORK_SERVICE="${NETWORK_SERVICE:-Wi-Fi}"

log() { printf '\033[1;36m==> %s\033[0m\n' "$*"; }

log "关闭代理: $NETWORK_SERVICE"
networksetup -setwebproxystate "$NETWORK_SERVICE" off
networksetup -setsecurewebproxystate "$NETWORK_SERVICE" off
networksetup -setsocksfirewallproxystate "$NETWORK_SERVICE" off

log "代理已关闭"
