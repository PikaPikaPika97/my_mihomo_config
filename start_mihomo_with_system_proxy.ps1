$ErrorActionPreference = 'SilentlyContinue'

# 配置参数
$controller_api = "http://127.0.0.1:9090"
$api_secret = ""
$task = "mihomo"
$proxy_port = 7890

# 自定义：不走系统代理的域名（默认包含 *.edu.cn 与 edu.cn）
$bypass_domains = @(
    "*.edu.cn", "edu.cn",
    "*.msftconnecttest.com", "msftconnecttest.com",
    "*.msftncsi.com", "msftncsi.com"
)

# 函数：弹窗通知
function Show-Notification {
    param($message)
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        $message,
        "系统代理模式已启用",
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

    # 2. 启用系统代理
    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name ProxyEnable -Value 1
    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name ProxyServer -Value "127.0.0.1:$proxy_port"
    $default_bypass = @(
        "localhost","127.*","10.*",
        "172.16.*","172.17.*","172.18.*","172.19.*","172.20.*","172.21.*","172.22.*","172.23.*","172.24.*","172.25.*","172.26.*","172.27.*","172.28.*","172.29.*","172.30.*","172.31.*",
        "192.168.*","<local>"
    )
    $proxy_override = ($default_bypass + $bypass_domains) -join ";"
    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name ProxyOverride -Value $proxy_override
    
    # 立即生效代理设置
    rundll32.exe wininet.dll,InternetSetOptionA 0 39 0 0
    rundll32.exe wininet.dll,InternetSetOptionA 0 37 0 0

    # 3. 禁用TUN模式
    $null = Invoke-RestMethod -Headers @{ "Authorization" = "Bearer $api_secret" } `
        -ContentType "application/json" `
        -Method PATCH `
        -Body '{"tun": {"enable": false}}' `
        -Uri "$controller_api/configs"

    # 成功反馈
    Write-Host "✅ 系统代理已启用 (端口 $proxy_port)" -ForegroundColor Green
    Write-Host "✅ TUN模式已禁用" -ForegroundColor Green
    Show-Notification "系统代理已启用`n端口: $proxy_port`nTUN模式已关闭"
}
catch {
    Write-Host "❌ 操作失败: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}