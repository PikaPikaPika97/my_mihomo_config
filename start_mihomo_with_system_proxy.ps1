param(
    [switch]$ShowNotification
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\mihomo_common.ps1"

try {
    Invoke-SystemProxyMode -ShowNotification:$ShowNotification
}
catch {
    Write-Host "❌ 系统代理模式切换失败: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
