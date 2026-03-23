# mihomo 裸核配置（精简版）

本仓库只保存 mihomo 的模板配置、控制脚本和计划任务文件。

## 不提交内容

- 本地覆盖：config.local.yaml
- 生成结果：official_config.yaml
- 运行缓存与下载：proxy_providers/、rules/、ui/、cache.db

## 核心文件

- official_config.template.yaml：主配置模板（可提交）
- config.local.example.yaml：本地覆盖示例（可提交）
- scripts/generate_config.py：合并模板和本地覆盖
- mihomo_common.ps1：脚本公共参数（任务名、端口、控制器地址）
- start_mihomo_with_system_proxy.ps1：切到系统代理模式
- start_mihomo_with_tun.ps1：切到 TUN 模式
- switch_mode.ps1：系统代理/TUN 一键切换
- use_desktop_mihomo.ps1：切到工位台式机代理
- use_local_mihomo.ps1：切回本机代理
- turnoff_system_proxy.ps1：仅关闭系统代理
- kill_mihomo.ps1：关闭代理并停止 mihomo

## 控制脚本结构

控制脚本采用“入口脚本 + 公共逻辑”结构：

- 入口层：start_mihomo_with_system_proxy.ps1、start_mihomo_with_tun.ps1、switch_mode.ps1、use_desktop_mihomo.ps1、use_local_mihomo.ps1、turnoff_system_proxy.ps1、kill_mihomo.ps1
- 公共层：mihomo_common.ps1（配置常量、控制器访问、系统代理读写、模式切换、停止流程）

入口层职责（保持很薄）：

- 接收参数（如 ShowNotification、Server）
- dot-source 加载 mihomo_common.ps1
- 调用对应 Invoke-* 函数
- 统一 try/catch 输出错误并返回非 0 退出码

公共层职责（集中复用）：

- 基础配置：ControllerApi、TaskName、ProxyPort、ApiSecret、重试/超时
- 系统代理：Set-SystemProxyEnabled、Set-SystemProxyDisabled、Set-SystemProxyServer
- 控制器联通与启动：Test-MihomoControllerAvailable、Wait-MihomoControllerReady、Ensure-MihomoRunning
- 模式切换：Set-TunMode、Invoke-SystemProxyMode、Invoke-TunMode、Invoke-SwitchMode
- 工位模式：Invoke-RemoteSystemProxyMode（先探测远端可达，再切系统代理）
- 收尾关闭：Invoke-TurnOffSystemProxy、Invoke-StopMihomo（停任务/杀进程/清 DNS）

典型执行链路：

- 系统代理模式：入口脚本 -> Invoke-SystemProxyMode -> Ensure-MihomoRunning + Set-SystemProxyEnabled + Set-TunMode(false)
- TUN 模式：入口脚本 -> Invoke-TunMode -> Ensure-MihomoRunning + Set-SystemProxyDisabled + Set-TunMode(true)
- 工位模式：入口脚本 -> Invoke-RemoteSystemProxyMode -> Test-TcpEndpoint + Set-SystemProxyServer(remote)
- 停止 mihomo：入口脚本 -> Invoke-StopMihomo -> 关闭系统代理 + 停任务/进程 + 清理 DNS

## 快速开始

### 1. 准备本地覆盖

```powershell
Copy-Item .\config.local.example.yaml .\config.local.yaml
```

至少补全 config.local.yaml 中的 proxy-providers。

### 2. 设置机器差异

笔记本独立模式（推荐）：

```yaml
bind-address: 127.0.0.1
allow-lan: false
```

台式机热点模式：

```yaml
bind-address: 0.0.0.0
allow-lan: true
```

控制器默认：

```yaml
external-controller: 127.0.0.1:9090
```

### 3. 生成运行配置

```powershell
pip install -r .\requirements.txt
python .\scripts\generate_config.py
```

生成规则：
- 输入：official_config.template.yaml + config.local.yaml
- 输出：official_config.yaml
- 失败时不会覆盖已有 official_config.yaml

## 运行方式

### 方式 A：前台运行（调试）

```powershell
.\mihomo-windows-amd64.exe -d .\ -f .\official_config.yaml
```

### 方式 B：计划任务运行（推荐日常）

可导入 mihomo.xml，或手动创建任务。

关键项：
- 任务名：mihomo
- 触发器：登录时
- 权限：使用最高权限运行
- 程序：mihomo-windows-amd64.exe
- 参数：-d .\ -f official_config.yaml
- 起始于：仓库根目录

仓库默认路径：

```text
C:\Users\YYH\OneDrive\Software\mihomo
```

如果迁移路径，需要同步修改 mihomo.xml 和脚本中的路径配置。

## 日常脚本

系统代理模式：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\start_mihomo_with_system_proxy.ps1
```

TUN 模式：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\start_mihomo_with_tun.ps1
```

自动切换模式：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\switch_mode.ps1
```

工位模式（使用台式机热点代理）：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\use_desktop_mihomo.ps1
```

自定义工位代理地址：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\use_desktop_mihomo.ps1 -Server "192.168.137.1:7890"
```

切回本机代理：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\use_local_mihomo.ps1
```

关闭系统代理：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\turnoff_system_proxy.ps1
```

停止 mihomo：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\kill_mihomo.ps1
```

## 控制器一致性

脚本通过控制器接口切换 TUN：

```text
PATCH /configs
```

默认控制器地址：

```text
127.0.0.1:9090
```

请保持以下一致：
- official_config.yaml 的 external-controller 字段
- mihomo_common.ps1 中控制器地址/任务名/端口
- 若启用 secret，脚本中的 ApiSecret 参数也要同步

## 常见问题

- TUN 切换失败：通常是权限不足，请使用管理员权限运行。
- 能启动但不能切换：先检查 127.0.0.1:9090 是否可达。
- 工位模式失败：检查 192.168.137.1:7890 是否连通。
- 改了端口无效：统一修改配置文件和脚本中的对应端口。
