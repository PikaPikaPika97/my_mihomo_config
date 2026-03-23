# mihomo 裸核配置（精简版）

这个仓库只保存 mihomo 模板配置、控制脚本和计划任务文件。

不提交敏感订阅和本机生成产物：
- 本地覆盖：config.local.yaml
- 生成结果：official_config.yaml
- 运行缓存与下载：proxy_providers/、rules/、ui/、cache.db

## 目录与核心文件

- official_config.template.yaml：主配置模板（可提交）
- config.local.example.yaml：本地覆盖示例
- scripts/generate_config.py：合并模板和本地覆盖
- mihomo_common.ps1：脚本公共配置（任务名、端口、控制器地址）
- start_mihomo_with_system_proxy.ps1：切到系统代理模式
- start_mihomo_with_tun.ps1：切到 TUN 模式
- switch_mode.ps1：系统代理/TUN 一键切换
- use_desktop_mihomo.ps1：切到工位台式机代理
- use_local_mihomo.ps1：切回本机代理
- turnoff_system_proxy.ps1：仅关闭系统代理
- kill_mihomo.ps1：关闭代理并停止 mihomo

## 仓库结构

```text
mihomo/
├─ official_config.template.yaml   # 主模板（可提交）
├─ config.local.example.yaml       # 本地覆盖示例（可提交）
├─ config.local.yaml               # 本地覆盖（不提交）
├─ official_config.yaml            # 生成后的运行配置（不提交）
├─ scripts/
│  └─ generate_config.py           # 配置生成脚本
├─ proxy_providers/                # provider 下载结果（不提交）
├─ rules/                          # 规则下载结果（不提交）
├─ ui/                             # 外部面板资源（不提交）
├─ mihomo_common.ps1               # 脚本公共参数
├─ start_mihomo_with_system_proxy.ps1
├─ start_mihomo_with_tun.ps1
├─ switch_mode.ps1
├─ use_desktop_mihomo.ps1
├─ use_local_mihomo.ps1
├─ turnoff_system_proxy.ps1
└─ kill_mihomo.ps1
```

## 快速开始

### 1. 准备本地配置

```powershell
Copy-Item .\config.local.example.yaml .\config.local.yaml
```

在 config.local.yaml 中至少补全你的 proxy-providers。

### 2. 填写机器差异

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

### 3. 安装依赖并生成配置

```powershell
pip install -r .\requirements.txt
python .\scripts\generate_config.py
```

生成规则：
- 输入：official_config.template.yaml + config.local.yaml
- 输出：official_config.yaml
- 失败时不会覆盖已有 official_config.yaml

### 4. 启动方式

推荐通过计划任务启动：

```powershell
mihomo-windows-amd64.exe -d .\ -f official_config.yaml
```

## 运行方法

### 方式 A：前台直接运行（调试最方便）

```powershell
.\mihomo-windows-amd64.exe -d .\ -f .\official_config.yaml
```

### 方式 B：登录后自动运行（推荐日常）

1. 导入 mihomo.xml 或手动创建计划任务。
2. 任务启动命令保持：

```powershell
mihomo-windows-amd64.exe -d .\ -f official_config.yaml
```

3. 日常通过下面的脚本切换模式，不直接改配置文件。

### 方式 C：脚本控制运行模式

- 系统代理模式：启动任务（如未运行）并切到系统代理
- TUN 模式：启动任务（如未运行）并切到 TUN
- 工位模式：切到台式机热点中的代理
- 本机模式：切回 127.0.0.1:7890

## 计划任务（最简）

可直接导入 mihomo.xml；若手动创建，关键项如下：
- 任务名：mihomo
- 触发器：登录时
- 权限：使用最高权限运行
- 程序：仓库中的 mihomo-windows-amd64.exe
- 参数：-d .\ -f official_config.yaml
- 起始于：仓库根目录

仓库默认路径：

```text
C:\Users\YYH\OneDrive\Software\mihomo
```

如果迁移路径，需要同步修改 mihomo.xml 和脚本中的路径配置。

## 常用脚本

- 系统代理模式：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\start_mihomo_with_system_proxy.ps1
```

- TUN 模式：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\start_mihomo_with_tun.ps1
```

- 自动切换模式：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\switch_mode.ps1
```

- 工位模式（使用台式机热点代理）：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\use_desktop_mihomo.ps1
```

自定义工位代理地址：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\use_desktop_mihomo.ps1 -Server "192.168.137.1:7890"
```

- 切回本机代理：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\use_local_mihomo.ps1
```

- 关闭系统代理：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\turnoff_system_proxy.ps1
```

- 停止 mihomo：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\kill_mihomo.ps1
```

## 控制器与一致性

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

- TUN 切换失败：通常是权限不足，使用管理员权限运行。
- 能启动但不能切换：先检查 127.0.0.1:9090 是否可达。
- 工位模式失败：检查 192.168.137.1:7890 是否连通。
- 改了端口无效：统一修改配置文件和脚本中的对应端口。
