$ErrorActionPreference = 'Stop'

# 配置参数
$controller_api = "http://127.0.0.1:9090"
$api_secret = ""
$proxy_port = 7890
$registryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'

# 自定义：不走系统代理的域名（可按需扩展）
$bypass_domains = @(
    "*.edu.cn", "edu.cn",
    "*.msftconnecttest.com", "msftconnecttest.com",
    "*.msftncsi.com", "msftncsi.com"
)

# 函数：统一注册表操作
function Update-ProxySettings {
    param(
        [bool]$enable,
        [string]$proxyServer = ""
    )
    try {
        Set-ItemProperty -Path $registryPath -Name ProxyEnable -Value ([int]$enable) -ErrorAction Stop
        Set-ItemProperty -Path $registryPath -Name ProxyServer -Value $proxyServer -ErrorAction Stop
        if ($enable) {
            $default_bypass = @(
                "localhost","127.*","10.*",
                "172.16.*","172.17.*","172.18.*","172.19.*","172.20.*","172.21.*","172.22.*","172.23.*","172.24.*","172.25.*","172.26.*","172.27.*","172.28.*","172.29.*","172.30.*","172.31.*",
                "192.168.*","<local>"
            )
            $proxy_override = ($default_bypass + $bypass_domains) -join ";"
            Set-ItemProperty -Path $registryPath -Name ProxyOverride -Value $proxy_override -ErrorAction Stop
        }
        
        # 双刷新机制确保立即生效
        rundll32.exe wininet.dll,InternetSetOptionA 0 39 0 0 | Out-Null
        rundll32.exe wininet.dll,InternetSetOptionA 0 37 0 0 | Out-Null
    }
    catch {
        Write-Host "❌ 代理设置失败: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

# 函数：增强API调用（含重试逻辑）
function Update-TunMode {
    param([bool]$enable)
    try {
        $body = @{ tun = @{ enable = $enable } } | ConvertTo-Json -Compress
        $null = Invoke-RestMethod -Headers @{ "Authorization" = "Bearer $api_secret" } `
            -ContentType "application/json" `
            -Method PATCH `
            -Body $body `
            -Uri "$controller_api/configs" `
            -ErrorAction Stop `
            -TimeoutSec 3  # 添加超时限制
        
        Write-Host "TUN模式已切换: $(if ($enable) {'启用'} else {'关闭'})" -ForegroundColor DarkGray
    }
    catch {
        Write-Host "❌ TUN模式切换失败: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

# 函数：增强型通知
function Show-SwitchStatus {
    param($proxyStatus, $tunStatus)
    Add-Type -AssemblyName System.Windows.Forms
    $icon = [System.Windows.Forms.MessageBoxIcon]::Information
    $title = "代理模式切换"
    
    # 控制台颜色反馈
    Write-Host "`n当前状态：" -ForegroundColor Cyan
    Write-Host "• 系统代理: $proxyStatus" -ForegroundColor $(if ($proxyStatus -eq "启用") { "Green" } else { "Yellow" })
    Write-Host "• TUN模式:  $tunStatus`n" -ForegroundColor $(if ($tunStatus -eq "启用") { "Green" } else { "Yellow" })
    
    # 弹窗通知
    [System.Windows.Forms.MessageBox]::Show(
        "系统代理: $proxyStatus`nTUN模式: $tunStatus",
        $title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        $icon
    )
    
    # 系统提示音
    [System.Media.SystemSounds]::Exclamation.Play()
}

try {
    # 获取当前代理状态
    $currentProxy = [bool](Get-ItemPropertyValue -Path $registryPath -Name ProxyEnable -ErrorAction Stop)

    # 核心切换逻辑
    if ($currentProxy) {
        Update-ProxySettings -enable $false
        Update-TunMode -enable $true
        Show-SwitchStatus -proxyStatus "关闭" -tunStatus "启用"
    }
    else {
        Update-ProxySettings -enable $true -proxyServer "127.0.0.1:$proxy_port"
        Update-TunMode -enable $false
        Show-SwitchStatus -proxyStatus "启用" -tunStatus "关闭"
    }
}
catch {
    Write-Host "`n❌ 切换失败: $($_.Exception.Message)" -ForegroundColor Red
    [System.Media.SystemSounds]::Hand.Play()
    exit 1
}