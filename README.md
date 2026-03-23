# mihomo 裸核自用配置

这个仓库只跟踪我自己的 `mihomo` 模板配置、控制脚本和计划任务导出文件，不跟踪机场订阅、本地机器差异和生成后的最终配置。

## 仓库内保留的文件

- `official_config.template.yaml`: 当前主配置模板，不包含敏感订阅信息。
- `config.local.example.yaml`: 本地覆盖文件示例。
- `my_config.yaml`: 早期或备用配置。
- `mihomo.xml`: Windows 计划任务导出文件。
- `mihomo_common.ps1`: 控制脚本共享函数和公共配置。
- `start_mihomo_with_system_proxy.ps1`: 启动/切换到本机系统代理模式。
- `start_mihomo_with_tun.ps1`: 启动/切换到 TUN 模式。
- `switch_mode.ps1`: 在本机系统代理模式和 TUN 模式之间切换。
- `turnoff_system_proxy.ps1`: 关闭系统代理。
- `kill_mihomo.ps1`: 关闭 mihomo 进程。
- `use_desktop_mihomo.ps1`: 切换到工位模式，使用台式机热点里的 mihomo。
- `use_local_mihomo.ps1`: 固定切回本机系统代理模式。
- `scripts/generate_config.py`: 合并模板和本地覆盖，生成最终 `official_config.yaml`。

## 不纳入版本控制的内容

这些文件或目录只保留在本地：

- `config.local.yaml`
- `official_config.yaml`
- `mihomo-windows-amd64.exe`
- `cache.db`
- `proxy_providers/`
- `rules/`
- `ui/`
- `meta-backup/`
- `__pycache__/`
- `.venv/`

## 目录约定

本仓库默认位于：

```text
C:\Users\YYH\OneDrive\Software\mihomo
```

计划任务和脚本都按这个路径编写。如果你把仓库移动到别的位置，需要同步修改：

- `mihomo.xml` 里的 `Command` 和 `WorkingDirectory`
- 脚本里引用的端口、任务名或路径

## 配置生成工作流

仓库只提交模板，敏感值和机器差异放在本地覆盖文件中。

### 1. 复制本地覆盖文件

先复制一份示例文件：

```powershell
Copy-Item ".\config.local.example.yaml" ".\config.local.yaml"
```

然后按机器实际情况填写。

至少需要在本地文件里完整定义你自己的 `proxy-providers`，例如：

```yaml
proxy-providers:
  provider1:
    url: "https://example.com/your-subscription"
    type: http
    interval: 21600
    path: ./proxy_providers/nano.yaml
    header:
      User-Agent:
        - "FlClash/v0.8.91 clash-verge Platform/windows"
    health-check:
      {
        enable: true,
        url: "https://www.gstatic.com/generate_204",
        interval: 300,
      }
    override:
      additional-prefix: "[nano]"
```

### 2. 填写机器差异

笔记本独立模式通常保持：

```yaml
bind-address: 127.0.0.1
allow-lan: false
```

台式机热点模式通常改成：

```yaml
bind-address: 0.0.0.0
allow-lan: true
```

控制器默认仍然保持：

```yaml
external-controller: 127.0.0.1:9090
```

### 3. 生成最终配置

如果 `python` 已在 PATH 中：

```powershell
python .\scripts\generate_config.py
```

如果本机是按用户目录安装 Python，也可以直接用解释器绝对路径：

```powershell
& "C:\Users\f403\AppData\Local\Python\bin\python.exe" ".\scripts\generate_config.py"
```

这里有一个约定：

- `proxy-providers` 整体由 `config.local.yaml` 提供
- 模板文件不再预设机场 provider 结构
- 这样不同机场的字段差异不会被模板绑定死

脚本会读取：

- `official_config.template.yaml`
- `config.local.yaml`

然后生成：

- `official_config.yaml`

生成失败时不会覆盖已有的 `official_config.yaml`。

### 4. 依赖安装

生成器依赖 `ruamel.yaml`：

```powershell
pip install -r .\requirements.txt
```

## mihomo 启动方式

当前使用方式是：

1. 通过 Windows 计划任务在登录时启动 `mihomo-windows-amd64.exe`
2. 运行参数使用仓库根目录作为工作目录
3. 使用本地生成的 `official_config.yaml` 作为主配置
4. 平时通过 PowerShell 脚本切换本机系统代理、TUN 模式或工位模式

计划任务实际执行的是：

```powershell
C:\Users\YYH\OneDrive\Software\mihomo\mihomo-windows-amd64.exe -d .\ -f official_config.yaml
```

其中：

- `-d .\` 表示运行目录就是仓库根目录，缓存、规则和 provider 落盘都相对这个目录。
- `-f official_config.yaml` 表示使用本地生成后的主配置文件启动。

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

### `start_mihomo_with_tun.ps1`

- 如果计划任务还没运行，先启动任务 `mihomo`
- 等待控制器 `127.0.0.1:9090` 就绪后再切换模式
- 关闭 Windows 系统代理
- 通过控制器 API 启用 mihomo 的 TUN 模式
- 适合不遵循系统代理的应用

### `switch_mode.ps1`

- 检查当前系统代理是否开启
- 如有需要，自动启动计划任务并等待控制器就绪
- 如果已开启，则切换为 TUN 模式
- 如果未开启，则切换为系统代理模式

### `use_desktop_mihomo.ps1`

- 默认探测 `192.168.137.1:7890` 是否可达
- 若不可达，直接失败并保持当前系统代理不变
- 若本机控制器可达，会先确保本机 TUN 模式关闭
- 将 Windows 系统代理直接切换到台式机热点里的 mihomo
- 适合笔记本在工位连接台式机热点时使用

默认指向：

```text
192.168.137.1:7890
```

运行示例：

```powershell
powershell -ExecutionPolicy Bypass -File .\use_desktop_mihomo.ps1
```

如果热点网关或端口变化，可显式传入：

```powershell
powershell -ExecutionPolicy Bypass -File .\use_desktop_mihomo.ps1 -Server "192.168.137.1:7890"
```

### `use_local_mihomo.ps1`

- 固定切回本机系统代理模式
- 会确保本机 mihomo 已运行
- 将 Windows 系统代理切回 `127.0.0.1:7890`
- 会通过控制器关闭 TUN 模式
- 不恢复历史状态，只恢复到本机系统代理模式

运行示例：

```powershell
powershell -ExecutionPolicy Bypass -File .\use_local_mihomo.ps1
```

### `turnoff_system_proxy.ps1`

- 关闭 Windows 系统代理
- 不负责关闭 mihomo 进程

### `kill_mihomo.ps1`

- 关闭系统代理
- 优先停止计划任务，再兜底结束 `mihomo-windows-amd64.exe`
- 同时清理 DNS 缓存

## 控制器接口

当前配置中控制器地址为：

```text
127.0.0.1:9090
```

脚本通过这个接口调用：

- `PATCH /configs` 切换 `tun.enable`

因此需要保证：

- `official_config.yaml` 中的 `external-controller` 与脚本一致
- 如果后续给控制器加了 `secret`，脚本中的 `ApiSecret` 也要同步修改
- 公共配置已集中到 `mihomo_common.ps1`，后续修改端口、任务名、控制器地址优先改这里

## 使用建议

- 切到 TUN 模式通常需要管理员权限，否则驱动或路由相关操作可能失败。
- 工位模式只建议在笔记本上使用；台式机本身作为热点出口时，直接运行本机 mihomo。
- 如果计划任务名称改了，记得同步修改脚本里的 `TaskName`。
- 如果代理端口改了，记得同步修改配置和脚本里的 `7890`。
- 如果控制器端口改了，记得同步修改配置和脚本里的 `9090`。
