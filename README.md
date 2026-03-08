# mihomo 裸核自用配置

这个仓库只跟踪我自己的 `mihomo` 配置、控制脚本和计划任务导出文件，不跟踪内核程序、规则缓存、订阅落盘文件和 UI 静态资源。

## 仓库内保留的文件

- `official_config.yaml`: 当前主配置。
- `my_config.yaml`: 早期或备用配置。
- `mihomo.xml`: Windows 计划任务导出文件。
- `mihomo_common.ps1`: 控制脚本共享函数和公共配置。
- `start_mihomo_with_system_proxy.ps1`: 启动/切换到系统代理模式。
- `start_mihomo_with_tun.ps1`: 启动/切换到 TUN 模式。
- `switch_mode.ps1`: 在系统代理模式和 TUN 模式之间切换。
- `turnoff_system_proxy.ps1`: 关闭系统代理。
- `kill_mihomo.ps1`: 关闭 mihomo 进程。

## 目录约定

本仓库默认位于：

```text
C:\Users\YYH\OneDrive\Software\mihomo
```

计划任务和脚本都按这个路径编写。如果你把仓库移动到别的位置，需要同步修改：

- `mihomo.xml` 里的 `Command` 和 `WorkingDirectory`
- 各脚本里引用的端口、任务名或路径

## mihomo 启动方式

当前使用方式是：

1. 通过 Windows 计划任务在登录时启动 `mihomo-windows-amd64.exe`
2. 运行参数使用仓库根目录作为工作目录
3. 使用 `official_config.yaml` 作为主配置
4. 平时通过 PowerShell 脚本切换系统代理模式或 TUN 模式

计划任务实际执行的是：

```powershell
C:\Users\YYH\OneDrive\Software\mihomo\mihomo-windows-amd64.exe -d .\ -f official_config.yaml
```

其中：

- `-d .\` 表示运行目录就是仓库根目录，缓存、规则和 provider 落盘都相对这个目录。
- `-f official_config.yaml` 表示使用主配置文件启动。

## 添加计划任务

### 方式一：直接导入 `mihomo.xml`

1. 打开“任务计划程序”。
2. 选择“导入任务”。
3. 选择仓库里的 `mihomo.xml`。
4. 导入后检查以下内容：
   - 任务名称为 `mihomo`
   - 触发器为“登录时”
   - 勾选“使用最高权限运行”
   - 程序路径指向当前仓库中的 `mihomo-windows-amd64.exe`
   - 工作目录指向当前仓库根目录

如果仓库路径不是 `C:\Users\YYH\OneDrive\Software\mihomo`，导入前先改 XML，或导入后在图形界面里改。

### 方式二：手动新建

在“任务计划程序”中新建任务，建议设置如下：

- 常规
  - 名称：`mihomo`
  - 使用最高权限运行
  - 用户登录时运行
- 触发器
  - 登录时
- 操作
  - 程序或脚本：`C:\Users\YYH\OneDrive\Software\mihomo\mihomo-windows-amd64.exe`
  - 添加参数：`-d .\ -f official_config.yaml`
  - 起始于：`C:\Users\YYH\OneDrive\Software\mihomo\`

## 控制脚本说明

### `start_mihomo_with_system_proxy.ps1`

- 如果计划任务还没运行，先启动任务 `mihomo`
- 等待控制器 `127.0.0.1:9090` 就绪后再切换模式
- 开启 Windows 系统代理到 `127.0.0.1:7890`
- 关闭 mihomo 的 TUN 模式
- 适合浏览器和遵循系统代理的应用

运行示例：

```powershell
powershell -ExecutionPolicy Bypass -File .\start_mihomo_with_system_proxy.ps1
```

启用弹窗通知：

```powershell
powershell -ExecutionPolicy Bypass -File .\start_mihomo_with_system_proxy.ps1 -ShowNotification
```

### `start_mihomo_with_tun.ps1`

- 如果计划任务还没运行，先启动任务 `mihomo`
- 等待控制器 `127.0.0.1:9090` 就绪后再切换模式
- 关闭 Windows 系统代理
- 通过控制器 API 启用 mihomo 的 TUN 模式
- 适合不遵循系统代理的应用

运行示例：

```powershell
powershell -ExecutionPolicy Bypass -File .\start_mihomo_with_tun.ps1
```

启用弹窗通知：

```powershell
powershell -ExecutionPolicy Bypass -File .\start_mihomo_with_tun.ps1 -ShowNotification
```

### `switch_mode.ps1`

- 检查当前系统代理是否开启
- 如有需要，自动启动计划任务并等待控制器就绪
- 如果已开启，则切换为 TUN 模式
- 如果未开启，则切换为系统代理模式

运行示例：

```powershell
powershell -ExecutionPolicy Bypass -File .\switch_mode.ps1
```

启用弹窗通知：

```powershell
powershell -ExecutionPolicy Bypass -File .\switch_mode.ps1 -ShowNotification
```

### `turnoff_system_proxy.ps1`

- 关闭 Windows 系统代理
- 不负责关闭 mihomo 进程

运行示例：

```powershell
powershell -ExecutionPolicy Bypass -File .\turnoff_system_proxy.ps1
```

### `kill_mihomo.ps1`

- 关闭系统代理
- 优先停止计划任务，再兜底结束 `mihomo-windows-amd64.exe`
- 同时清理 DNS 缓存

运行示例：

```powershell
powershell -ExecutionPolicy Bypass -File .\kill_mihomo.ps1
```

## 控制器接口

当前配置中控制器地址为：

```text
127.0.0.1:9090
```

脚本通过这个接口调用：

- `PATCH /configs` 切换 `tun.enable`

因此需要保证：

- `official_config.yaml` 中的 `external-controller` 与脚本一致
- 如果后续给控制器加了 `secret`，脚本中的 `$api_secret` 也要同步修改
- 公共配置已集中到 `mihomo_common.ps1`，后续修改端口、任务名、控制器地址优先改这里

## 使用建议

- 切到 TUN 模式通常需要管理员权限，否则驱动或路由相关操作可能失败。
- 如果计划任务名称改了，记得同步修改脚本里的 `$task = "mihomo"`。
- 如果代理端口改了，记得同步修改配置和脚本里的 `7890`。
- 如果控制器端口改了，记得同步修改配置和脚本里的 `9090`。

## 不纳入版本控制的内容

这些内容是运行产物或第三方文件，默认忽略：

- `mihomo-windows-amd64.exe`
- `cache.db`
- `proxy_providers/`
- `rules/`
- `ui/`
- `meta-backup/`
- 快捷方式目录和其他临时文件
