param(
    [switch]$ShowNotification
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\mihomo_common.ps1"

try {
    Invoke-TurnOffSystemProxy -ShowNotification:$ShowNotification
}
catch {
    Write-Host "❌ 关闭代理失败: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
