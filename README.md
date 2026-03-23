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
powershell -ExecutionPolicy Bypass -File .\start_mihomo_with_system_proxy.ps1
```

- TUN 模式：

```powershell
powershell -ExecutionPolicy Bypass -File .\start_mihomo_with_tun.ps1
```

- 自动切换模式：

```powershell
powershell -ExecutionPolicy Bypass -File .\switch_mode.ps1
```

- 工位模式（使用台式机热点代理）：

```powershell
powershell -ExecutionPolicy Bypass -File .\use_desktop_mihomo.ps1
```

自定义工位代理地址：

```powershell
powershell -ExecutionPolicy Bypass -File .\use_desktop_mihomo.ps1 -Server "192.168.137.1:7890"
```

- 切回本机代理：

```powershell
powershell -ExecutionPolicy Bypass -File .\use_local_mihomo.ps1
```

- 关闭系统代理：

```powershell
powershell -ExecutionPolicy Bypass -File .\turnoff_system_proxy.ps1
```

- 停止 mihomo：

```powershell
powershell -ExecutionPolicy Bypass -File .\kill_mihomo.ps1
```

## 控制器与一致性

脚本通过控制器接口切换 TUN：PATCH /configs。

默认控制器地址：127.0.0.1:9090

请保持以下一致：
- official_config.yaml 的 external-controller
- mihomo_common.ps1 中控制器地址/任务名/端口
- 若启用 secret，脚本中的 ApiSecret 也要同步

## 常见问题

- TUN 切换失败：通常是权限不足，使用管理员权限运行。
- 能启动但不能切换：先检查 127.0.0.1:9090 是否可达。
- 工位模式失败：检查 192.168.137.1:7890 是否连通。
- 改了端口无效：统一修改配置文件和脚本中的对应端口。
