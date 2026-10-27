# 问题排查

记录已遇到的问题、排查方法和处理步骤。

## 常规检查

- TUN 切换失败时，使用管理员权限运行命令。
- 控制器不可达时，检查 `127.0.0.1:9090`。
- 远端代理失败时，检查 `RemoteServer` 地址和端口。
- 计划任务查询显示不存在时，先用管理员 PowerShell 重试。
- 修改端口后，检查配置文件和控制模块中的端口是否一致。

## Windows 计划任务返回 `0xC0000142`

遇到过的现象是：旧的 mihomo 计划任务启动失败，任务返回 `0xC0000142`。当时工作区可能带有 AI 沙箱留下的 `Low` 完整性标签。这个返回码本身不足以判断原因，需要结合任务使用的程序路径和文件完整性标签排查。

旧方案递归把工作区设为 `Medium`。这虽能让内核启动，也会限制内核进程的完整性级别。随后开启 TUN 时，即使任务使用 SYSTEM，仍会报 `A required privilege is not held by the client`。

处理方法是在当前用户的管理员 PowerShell 7 中，从仓库根目录重新运行 Windows 安装脚本：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\install_config.ps1
```

当前安装脚本把程序部署到 `%ProgramFiles%\mihomo`，把配置和运行数据放到 `%ProgramData%\mihomo`。脚本写入文件内容，避免复制工作区的 ACL，并在安装时将内核标记为 `High`。计划任务使用独立安装目录中的内核，启动时不再修改仓库 ACL。

安装后，检查计划任务 `mihomo` 的程序路径和数据目录是否指向上述位置，再验证任务启动和 TUN 开关。若仍失败，检查任务返回码和内核日志，继续按实际错误排查。

## Selector 分组选定节点或分组后仍会自动切换

`type: select` 按完整名称保存所选项。只要所选项仍在候选列表中，测速超时或连接失败不会让 Selector 自动换到其他项。出现切换时，先区分是 Selector 的选中项变化，还是所选子分组内部的节点变化。

- 选中的是 `url-test` 或 `fallback` 子分组时，子分组仍会自动选择节点。需要固定出口时，在 Selector 中直接选择具体节点。
- 订阅更新、过滤条件变化或配置修改后，检查原选中项的完整名称是否仍在候选列表中。节点或子分组改名、删除后，Selector 匹配不到原名称，会使用候选列表的第一项。若第一项是自动选择分组，就会表现为又开始自动换节点。
- 仅在重启或重载配置后丢失选择时，检查 `profile.store-selected: true` 是否生效。还要检查内核数据目录（`-d` 参数）是否变化，以及 `cache.db` 是否保留并可读写。保存选择无法解决选中项改名的问题。

一种实际遇到的情况是：订阅把剩余流量和天数放进节点名，例如 `US-01|📊100.00GB|⏳91D`。更新后变成 `US-01|📊99.29GB|⏳90D`，Mihomo 就会把它当成另一个名称。可在 `config.local.yaml` 对应 provider 的 `override` 中加入名称替换规则，去掉动态后缀：

```yaml
override:
  # 保留此处已有的 additional-prefix、dialer-proxy 等配置。
  proxy-name:
    - pattern: '\|📊[^|]+\|⏳[^|]+$'
      target: ""
```

这条规则只适用于示例中的后缀格式，其他格式需调整正则表达式。替换后应保留稳定且唯一的节点名称，避免把不同节点改成同名。重新运行对应平台的安装脚本使配置生效，再在面板中选择一次新名称。之后更新订阅，确认完整名称和选中项都保持不变。

参考：[Selector 的名称匹配与首项回退实现](https://github.com/MetaCubeX/mihomo/blob/v1.19.33/adapter/outboundgroup/selector.go#L96-L105)、[provider 名称替换配置](https://wiki.metacubex.one/config/proxy-providers/#overrideproxy-name)。
