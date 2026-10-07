# mihomo 配置仓库

本仓库保存 mihomo 配置模板、控制脚本和安装脚本。配置步骤在所有平台相同，使用方式按平台分节说明。你需要自备私有配置和 mihomo 可执行文件。

## 准备工具

所有平台都需要：

- [uv](https://docs.astral.sh/uv/)，用于运行 Python 脚本
- mihomo，用于运行代理内核

Windows 还需要：

- PowerShell 7，用于运行代理控制脚本

macOS 和 Linux 还需要：

- [Homebrew](https://brew.sh)，用于安装和运行 mihomo

每个 Python 脚本在文件头声明 Python 版本和依赖。本仓库不使用 `requirements.txt`。

## 通用配置

以下步骤在所有平台上相同。

### 复制本地配置

把 `config.local.example.yaml` 复制为 `config.local.yaml`：

```powershell
Copy-Item .\config.local.example.yaml .\config.local.yaml
```

在 `config.local.yaml` 中填写：

- `proxy-providers`，你的订阅地址
- 监听地址，按机器用途选择

独立使用：

```yaml
bind-address: 127.0.0.1
allow-lan: false
```

为局域网提供代理：

```yaml
bind-address: 0.0.0.0
allow-lan: true
```

保留默认控制器地址 `127.0.0.1:9090`，除非你同步修改控制脚本。

把 `proxy_bypass.local.example.yaml` 复制为 `proxy_bypass.local.yaml`：

```powershell
Copy-Item .\proxy_bypass.local.example.yaml .\proxy_bypass.local.yaml
```

在 `proxy_bypass.local.yaml` 中填入本机私有的 bypass 项，例如公司内网域名。

### 生成运行配置

运行配置生成脚本：

```powershell
uv run --script .\scripts\generate_config.py
```

脚本读取 `official_config.template.yaml` 和 `config.local.yaml`，合并后写入 `official_config.yaml`。它验证 `proxy-providers`。失败时保留已有的 `official_config.yaml`。

### 解析代理 bypass

bypass 列表是不走代理、直接连接的域名和网段。脚本合并 `proxy_bypass.yaml` 和可选的 `proxy_bypass.local.yaml`，按平台输出格式。

Windows：

```powershell
uv run --script .\scripts\resolve_proxy_bypass.py --platform windows
```

macOS：

```bash
uv run --script scripts/resolve_proxy_bypass.py --platform macos
```

Linux：

```bash
uv run --script scripts/resolve_proxy_bypass.py --platform linux
```

## Windows

### 安装配置和内核

在当前用户的管理员 PowerShell 7 中运行（使用 UAC 提升当前账户，不要换成另一个管理员账户）：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\install_config.ps1
```

默认从仓库根目录读取 `mihomo-windows-amd64.exe`。也可以指定内核来源：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\install_config.ps1 -MihomoExecutable 'D:\Downloads\mihomo-windows-amd64.exe'
```

脚本生成并校验配置、解析 bypass，然后停止已有内核，部署文件并启动新的 `mihomo` 计划任务。安装失败会报告错误；部署阶段失败后，修复原因并重新运行脚本。

| 安装位置 | 内容 |
| --- | --- |
| `%ProgramFiles%\mihomo` | 内核、`mihomo.ps1`、控制模块 |
| `%ProgramData%\mihomo` | `config.yaml`、生成的 `proxy_bypass.txt`、任务导出 `mihomo.xml`，以及内核下载的规则、订阅、面板和缓存 |
| 当前用户开始菜单的 `mihomo` 目录 | 本机系统代理、本机 TUN、切换模式、直连和停止快捷方式 |

计划任务使用 `SYSTEM` 最高权限，在开机时启动；程序和工作目录使用安装时计算的绝对路径。快捷方式以管理员权限运行当前用户的控制脚本，系统代理写入该用户的 HKCU。日常操作不再依赖仓库或 uv。

换机器、移动仓库、修改配置或更新内核后，重新运行安装脚本即可。它会替换旧的同名计划任务，无需手改 XML 或快捷方式路径。原仓库中的缓存和面板不迁移，新数据目录会按配置重新下载；自定义配置引用的本地文件需要放入数据目录，或使用绝对路径。

安装后的手动控制命令：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$env:ProgramFiles\mihomo\mihomo.ps1" -ProxyBypassFile "$env:ProgramData\mihomo\proxy_bypass.txt" -State LocalSystemProxy
```

### 前台调试

前台启动适合调试：

```powershell
.\mihomo-windows-amd64.exe -d .\ -f .\official_config.yaml
```

### 切换代理状态

所有 Windows 代理操作都使用 `mihomo.ps1`。完整命令：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\mihomo.ps1 -State LocalSystemProxy
```

5 种目标状态：

| 目标状态 | 参数 | 结果 |
| --- | --- | --- |
| 本机系统代理 | `-State LocalSystemProxy` | 本机内核运行，TUN 关闭，系统代理指向本机端口 |
| 本机 TUN | `-State LocalTun` | 本机内核运行，系统代理关闭，TUN 开启 |
| 直连 | `-State Direct` | 本机内核运行，系统代理和 TUN 都关闭 |
| 远端代理 | `-State RemoteProxy -RemoteServer "192.168.137.1:7890"` | 系统代理指向远端地址，本机内核停止 |
| 停止 | `-State Stopped` | 系统代理关闭，本机任务和进程停止 |

TUN 是 mihomo 的虚拟网卡模式，接管系统所有流量。

在 2 个本机代理状态之间切换：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\mihomo.ps1 -ToggleLocal
```

`ToggleLocal` 只接受完整的本机系统代理状态或本机 TUN 状态。它在直连、远端、停止或混合状态下拒绝操作。此时请显式指定 `-State`。

快捷方式使用 `-ShowNotification` 显示结果。手动运行默认不弹窗。上面的仓库命令在启用系统代理时通过 uv 解析 bypass；安装后的快捷方式使用安装时生成的 bypass 文件。

### 验证 Windows 状态

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

## macOS

### 安装配置

生成、验证并安装配置：

```bash
bash scripts/macos/install_config.sh
```

不要用 `sudo` 运行安装配置脚本。它需要在当前用户的 Homebrew 环境中生成配置并重启用户级服务。

### 开启或关闭系统代理

```bash
sudo bash scripts/macos/proxy_on.sh
sudo bash scripts/macos/proxy_off.sh
```

这两个脚本使用 `networksetup` 修改系统网络服务，因此需要管理员权限。`proxy_off` 只关闭代理状态，不清空 bypass，避免破坏公司原有的 bypass 配置。

### 使用终端代理

终端代理只修改当前 Bash 或 zsh 会话的环境变量，不需要 `sudo`：

```zsh
source scripts/macos/terminal_proxy.sh
proxy_on
proxy_status
proxy_off
```

建议把 `source` 写入 Bash 的 `~/.bashrc` 或 zsh 的 `~/.zshrc`。默认端口为 7890，可用 `MIHOMO_PROXY_PORT` 覆盖。

## Linux

### 安装配置

生成、验证并安装配置：

```bash
bash scripts/linux/install_config.sh
```

不要用 `sudo` 运行安装配置脚本。它会把配置写入当前用户的 Linuxbrew 目录，并通过 `brew services` 管理用户级 systemd 服务。

首次安装服务可执行：

```bash
brew services start mihomo
```

之后每次更新配置只需再次运行 `install_config.sh`；脚本会重启服务。

### 使用终端代理

终端代理只修改当前 Bash 或 zsh 会话的环境变量，不需要 `sudo`：

```zsh
source scripts/linux/terminal_proxy.sh
proxy_on
proxy_status
proxy_off
```

建议把 `source` 写入 Bash 的 `~/.bashrc` 或 zsh 的 `~/.zshrc`。默认端口为 7890，可用 `MIHOMO_PROXY_PORT` 覆盖。

Linux 没有统一的系统代理命令，因此未提供与 macOS `networksetup` 对应的全局代理脚本。若需要图形桌面的系统代理，请按使用的桌面环境（例如 GNOME 或 KDE）单独实现。

## 排查问题

- TUN 切换失败时，使用管理员权限运行命令
- 控制器不可达时，检查 `127.0.0.1:9090`
- 远端代理失败时，检查 `RemoteServer` 地址和端口
- 计划任务查询显示不存在时，先用管理员 PowerShell 重试
- 修改端口后，检查配置文件和控制模块中的端口是否一致
- 旧任务返回 `0xC0000142` 时，可能是 AI 沙箱给工作区留下了 `Low` 完整性标签。旧方案递归设为 `Medium` 虽能启动内核，也会限制内核进程的完整性级别，使 TUN 报 `A required privilege is not held by the client`，即使任务使用 SYSTEM 也会失败。重新运行 Windows 安装脚本迁移到独立安装目录；脚本写入文件内容并在安装时将内核标记为 `High`，任务启动时不再修改仓库 ACL。

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

修改配置时，保持以下值一致：

- `official_config.yaml` 中的 `external-controller`
- `scripts/windows/MihomoControl.psm1` 中的控制器地址、任务名和端口
- 启用控制器 secret 时，`scripts/windows/MihomoControl.psm1` 中的 `ApiSecret`

## 设计和架构

### 核心文件

- `official_config.template.yaml` 保存可提交的主配置模板
- `config.local.example.yaml` 提供本地配置示例
- `scripts/generate_config.py` 合并并验证 mihomo 配置
- `scripts/resolve_proxy_bypass.py` 生成各平台使用的 bypass 列表
- `mihomo.ps1` 是 Windows 命令入口
- `scripts/windows/MihomoControl.psm1` 管理 Windows 目标代理状态
- `scripts/windows/install_config.ps1` 部署 Windows 程序和配置，注册计划任务并生成快捷方式
- `CONTEXT.md` 定义代理控制领域词汇

### Windows 模块分工

Windows 控制代码分为一个命令入口和一个状态模块。

`mihomo.ps1` 是命令入口，负责：

- 接收目标状态或 `ToggleLocal`
- 导入状态模块
- 设置退出码
- 输出结果和可选通知

`scripts/windows/MihomoControl.psm1` 是状态模块，只导出 2 个函数：

- `Set-MihomoTargetState` 收敛到显式目标状态
- `Switch-MihomoLocalMode` 在 2 个本机代理状态之间切换

模块内部处理注册表、WinINet、控制器、计划任务、进程、DNS、bypass 和 TCP 探测。调用者不能直接组合这些操作。

### 状态转换规则

显式目标状态支持重复执行。重复执行不会累积副作用。

状态转换遵循以下规则：

- 同一时间只允许一个转换进程
- 转换失败后不自动回滚
- 错误会列出失败步骤和可能的中间状态，并附上原始错误
- 部分失败后，重新执行同一个显式 `-State`
- 部分失败后，不要重试 `ToggleLocal`

### Python 脚本依赖

每个 Python 脚本使用 PEP 723 元数据声明 Python 版本和依赖。`uv run --script` 会创建隔离环境并安装所需依赖。

本仓库不使用 `requirements.txt`、`pyproject.toml` 或 `uv.lock` 管理这些单文件脚本。
