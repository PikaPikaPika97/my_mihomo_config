$ErrorActionPreference = 'SilentlyContinue'

# 函数：弹窗通知
function Show-Notification {
    param($message)
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        $message,
        "系统代理设置",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
}

try {
    # 1. 禁用系统代理注册表设置
    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' `
        -Name ProxyEnable `
        -Value 0 `
        -ErrorAction Stop

    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' `
        -Name ProxyServer `
        -Value "" `
        -ErrorAction Stop

    # 2. 立即生效代理设置
    rundll32.exe wininet.dll,InternetSetOptionA 0 39 0 0
    rundll32.exe wininet.dll,InternetSetOptionA 0 37 0 0

    # 3. 反馈结果
    Write-Host "✅ 系统代理已关闭" -ForegroundColor Green
    Show-Notification "系统代理已成功关闭"
}
catch {
    Write-Host "❌ 关闭代理失败: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}