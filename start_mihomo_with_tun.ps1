$ErrorActionPreference = 'SilentlyContinue'

# 配置参数
$controller_api = "http://127.0.0.1:9090"
$api_secret = ""
$task = "mihomo"

# 函数：弹窗通知
function Show-Notification {
    param($message)
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        $message,
        "TUN模式已启用",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
}

try {
    # 1. 检查并启动内核
    $state = Get-ScheduledTask -TaskName $task | Select-Object -ExpandProperty State
    if ($state -ne "Running") {
        Start-ScheduledTask -TaskName $task
        Start-Sleep -Seconds 3
        $state = Get-ScheduledTask -TaskName $task | Select-Object -ExpandProperty State
        if ($state -ne "Running") {
            Write-Host "❌ 启动内核失败" -ForegroundColor Red
            exit 1
        }
    }

    # 2. 关闭系统代理
    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name ProxyEnable -Value 0
    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name ProxyServer -Value ""
    
    # 立即生效代理设置
    rundll32.exe wininet.dll,InternetSetOptionA 0 39 0 0
    rundll32.exe wininet.dll,InternetSetOptionA 0 37 0 0

    # 3. 启用TUN模式
    $null = Invoke-RestMethod -Headers @{ "Authorization" = "Bearer $api_secret" } `
        -ContentType "application/json" `
        -Method PATCH `
        -Body '{"tun": {"enable": true}}' `
        -Uri "$controller_api/configs"

    # 成功反馈
    Write-Host "✅ 系统代理已关闭" -ForegroundColor Green
    Write-Host "✅ TUN模式已启用" -ForegroundColor Green
    Show-Notification "系统代理已关闭`nTUN模式已启用"
}
catch {
    Write-Host "❌ 操作失败: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}