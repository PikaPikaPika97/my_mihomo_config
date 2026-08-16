# mihomo 裸核配置

本仓库保存 mihomo 配置模板、控制脚本和计划任务定义。你需要在本机提供私有配置和 mihomo 可执行文件。

## 开始使用

### 准备工具

安装以下工具：

- [uv](https://docs.astral.sh/uv/)，用于运行 Python 脚本和安装脚本声明的依赖
- PowerShell 7，用于运行 Windows 代理控制脚本
- mihomo，用于运行代理内核

本仓库不使用 `requirements.txt`。每个 Python 脚本都在文件头声明 Python 版本和依赖。

### 创建本地配置

1. 复制本地配置示例。

   ```powershell
   Copy-Item .\config.local.example.yaml .\config.local.yaml
   ```

2. 在 `config.local.yaml` 中填写 `proxy-providers`。

3. 按机器用途设置监听地址。

   独立使用：

   ```yaml
   bind-address: 127.0.0.1
   allow-lan: false
   ```

   提供局域网代理：

   ```yaml
   bind-address: 0.0.0.0
   allow-lan: true
   ```

4. 保留默认控制器地址，除非你也会同步修改控制脚本。

   ```yaml
   external-controller: 127.0.0.1:9090
   ```

### 生成运行配置

运行配置生成脚本：

```powershell
uv run --script .\scripts\generate_config.py
```

脚本执行以下操作：

- 读取 `official_config.template.yaml`
- 合并 `config.local.yaml`
- 验证 `proxy-providers`
- 写入 `official_config.yaml`
- 失败时保留已有的 `official_config.yaml`

### 启动 mihomo

前台启动适合调试：

```powershell
.\mihomo-windows-amd64.exe -d .\ -f .\official_config.yaml
```

日常使用建议导入 `mihomo.xml`，或手动创建计划任务。计划任务需要以下设置：

- 任务名为 `mihomo`
- 用户登录时触发
- 使用最高权限运行
- 程序为 `mihomo-windows-amd64.exe`
- 参数为 `-d .\ -f official_config.yaml`
- 工作目录为仓库根目录

仓库当前使用以下默认路径：

```text
C:\Users\YYH\OneDrive\Software\mihomo
```

迁移仓库后，需要同步更新 `mihomo.xml` 和控制脚本中的路径。

### 切换 Windows 代理状态

所有 Windows 代理操作都使用 `mihomo.ps1`。

| 目标状态 | 命令 | 结果 |
| --- | --- | --- |
| 本机系统代理 | `pwsh -NoProfile -ExecutionPolicy Bypass -File .\mihomo.ps1 -State LocalSystemProxy` | 本机内核运行，TUN 关闭，系统代理指向本机端口 |
| 本机 TUN | `pwsh -NoProfile -ExecutionPolicy Bypass -File .\mihomo.ps1 -State LocalTun` | 本机内核运行，系统代理关闭，TUN 开启 |
| 直连 | `pwsh -NoProfile -ExecutionPolicy Bypass -File .\mihomo.ps1 -State Direct` | 本机内核运行，系统代理和 TUN 都关闭 |
| 远端代理 | `pwsh -NoProfile -ExecutionPolicy Bypass -File .\mihomo.ps1 -State RemoteProxy -RemoteServer "192.168.137.1:7890"` | 系统代理指向远端地址，本机内核停止 |
| 停止 | `pwsh -NoProfile -ExecutionPolicy Bypass -File .\mihomo.ps1 -State Stopped` | 系统代理关闭，本机任务和进程停止 |

在 2 个本机代理状态之间切换：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\mihomo.ps1 -ToggleLocal
```

`ToggleLocal` 只接受完整的本机系统代理状态或本机 TUN 状态。它在直连、远端、停止或混合状态下会拒绝操作。此时请显式指定 `-State`。

快捷方式使用 `-ShowNotification` 显示结果。手动运行默认不弹窗。

### 使用 macOS 脚本

生成、验证并安装配置：

```bash
bash scripts/macos/install_config.sh
```

不要用 `sudo` 运行安装配置脚本。它需要在当前用户的 Homebrew 环境中生成配置并重启用户级服务。

开启或关闭 macOS 系统代理：

```bash
sudo bash scripts/macos/proxy_on.sh
sudo bash scripts/macos/proxy_off.sh
```

这两个脚本使用 `networksetup` 修改系统网络服务，因此需要管理员权限。终端代理只修改当前 zsh 会话的环境变量，不需要 `sudo`。

在当前 zsh 会话中加载终端代理命令：

```zsh
source scripts/macos/terminal_proxy.sh
proxy_on
proxy_status
proxy_off
```

### 解析代理 bypass

Windows 格式：

```powershell
uv run --script .\scripts\resolve_proxy_bypass.py --platform windows
```

macOS 格式：

```bash
uv run --script scripts/resolve_proxy_bypass.py --platform macos
```

脚本会合并 `proxy_bypass.yaml` 和可选的 `proxy_bypass.local.yaml`。

## 手动验证 Windows 状态

真实状态验证会修改当前机器的代理、TUN 和 mihomo 进程。请按顺序执行。

1. 确认管理员 PowerShell 可以运行 `Get-ScheduledTask -TaskName mihomo`。普通权限可能无法查看任务。
2. 进入 `LocalSystemProxy`。确认 `ProxyEnable=1`、`ProxyServer=127.0.0.1:7890` 且 TUN 关闭。重复执行一次，确认结果不变。
3. 执行 `ToggleLocal`。确认系统进入 `LocalTun`，系统代理清空且 TUN 开启。再次执行应回到 `LocalSystemProxy`。
4. 进入 `Direct`。确认系统代理和 TUN 都关闭，控制器仍可用。此时执行 `ToggleLocal` 应拒绝操作且不修改状态。
5. 使用不可达地址执行 `RemoteProxy`。确认脚本在修改当前状态前失败。仅在远端出口可用时验证成功路径。
6. 快速连续启动 2 个不同快捷方式。确认第二个调用因已有切换正在执行而失败。
7. 最后进入 `Stopped`。确认系统代理清空、计划任务未运行且 mihomo 进程不存在。

检查 Windows 系统代理：

```powershell
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' |
    Select-Object ProxyEnable, ProxyServer
```

检查控制器和 TUN：

```powershell
(Invoke-RestMethod http://127.0.0.1:9090/configs).tun
```

## 配置参考

### 不提交本机数据

以下文件和目录只保留在本机：

- `config.local.yaml`
- `official_config.yaml`
- `proxy_bypass.local.yaml`
- `proxy_providers/`
- `rules/`
- `ui/`
- `cache.db`

### 保持控制器设置一致

控制脚本通过 `PATCH /configs` 切换 TUN。默认控制器地址为 `127.0.0.1:9090`。

修改配置时，需要保持以下值一致：

- `official_config.yaml` 中的 `external-controller`
- `MihomoControl.psm1` 中的控制器地址、任务名和端口
- 启用控制器 secret 时，`MihomoControl.psm1` 中的 `ApiSecret`

## 设计和架构

### 核心文件

- `official_config.template.yaml` 保存可提交的主配置模板
- `config.local.example.yaml` 提供本地配置示例
- `scripts/generate_config.py` 合并并验证 mihomo 配置
- `scripts/resolve_proxy_bypass.py` 生成各平台使用的 bypass 列表
- `mihomo.ps1` 是 Windows 命令入口
- `MihomoControl.psm1` 管理 Windows 目标代理状态
- `CONTEXT.md` 定义代理控制领域词汇

### Windows 模块分工

Windows 控制代码分为一个命令入口和一个状态模块。

`mihomo.ps1` 是命令 adapter，负责：

- 接收目标状态或 `ToggleLocal`
- 导入状态 module
- 设置退出码
- 输出结果和可选通知

`MihomoControl.psm1` 是状态 module，只导出以下 2 个函数：

- `Set-MihomoTargetState` 收敛到显式目标状态
- `Switch-MihomoLocalMode` 在 2 个本机代理状态之间切换

module 内部处理注册表、WinINet、控制器、计划任务、进程、DNS、bypass 和 TCP 探测。调用者不能直接组合这些操作。

### 状态转换规则

显式目标状态支持重复执行。重复执行不会累积副作用。

状态转换遵循以下规则：

- 同一时间只允许一个转换进程
- 转换失败后不自动回滚
- 错误会列出失败步骤和可能的中间状态，并附上原始错误
- 部分失败后，应重新执行同一个显式 `-State`
- 部分失败后，不应重试 `ToggleLocal`

### Python 脚本依赖

每个 Python 脚本使用 PEP 723 元数据声明 Python 版本和依赖。`uv run --script` 会创建隔离环境并安装所需依赖。

仓库不使用 `requirements.txt`、`pyproject.toml` 或 `uv.lock` 管理这些单文件脚本。

## 排查问题

- TUN 切换失败时，使用管理员权限运行命令
- 控制器不可达时，检查 `127.0.0.1:9090`
- 远端代理失败时，检查 `RemoteServer` 地址和端口
- 计划任务查询显示不存在时，先用管理员 PowerShell 重试
- 修改端口后，检查配置文件和控制 module 中的端口是否一致
