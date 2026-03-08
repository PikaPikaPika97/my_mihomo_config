param(
    [switch]$ShowNotification
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\mihomo_common.ps1"

try {
    Invoke-StopMihomo -ShowNotification:$ShowNotification
}
catch {
    Write-Host "❌ 关闭 mihomo 失败: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
