# zashboard TUN 开关源码核查

核查日期：2026-09-06。范围为官方上游源码，不代表已核对本机安装版本；未操作本机 API、系统代理或配置文件。

源码基准：zashboard `main` 提交 [64b945828c](https://github.com/Zephyruso/zashboard/commit/64b945828c2b4fbae498dc21f8582b60945ad0ed)；mihomo `Meta` 提交 [ac017cdd24](https://github.com/MetaCubeX/mihomo/commit/ac017cdd246ce8bd547653d927e7bf77d7ee73d5)。以下链接固定到核查提交。

## 简短发现

1. **调用方式：PATCH /configs。** 复选框绑定 `configs.tun.enable`，变更时执行 `updateConfigs({ tun: { enable: ... } })`；Clash 后端发送 JSON `{"tun":{"enable":true}}`（关闭为 `false`），完成后 GET `/configs` 回读。请求发往当前选中的后端，附带 `Authorization: Bearer <password>`。[开关处理](https://github.com/Zephyruso/zashboard/blob/64b945828c2b4fbae498dc21f8582b60945ad0ed/src/components/settings/backend/BackendSettings.vue#L212-L218)、[配置封装](https://github.com/Zephyruso/zashboard/blob/64b945828c2b4fbae498dc21f8582b60945ad0ed/src/assembly/config/clash.ts#L5-L12)、[API](https://github.com/Zephyruso/zashboard/blob/64b945828c2b4fbae498dc21f8582b60945ad0ed/src/api/clash.ts#L123-L129)、[请求目标与鉴权](https://github.com/Zephyruso/zashboard/blob/64b945828c2b4fbae498dc21f8582b60945ad0ed/src/api/http.ts#L10-L16)。

2. **配置层面只改运行时，不写回 YAML。** mihomo 将请求中的 `enable` 合入 `listener.LastTunConf`，未提供的 TUN 参数沿用原值，再调用 `ReCreateTun`。该 PATCH 路径没有配置文件保存操作；它会实际关闭／创建 TUN 监听器，所以“只改运行时”不等于“只改界面、没有网络效果”。开关也不会自动补齐 `auto-route` 等参数。[参数合并](https://github.com/MetaCubeX/mihomo/blob/ac017cdd246ce8bd547653d927e7bf77d7ee73d5/hub/route/configs.go#L141-L158)、[完整 PATCH 处理](https://github.com/MetaCubeX/mihomo/blob/ac017cdd246ce8bd547653d927e7bf77d7ee73d5/hub/route/configs.go#L320-L389)、[启停实现](https://github.com/MetaCubeX/mihomo/blob/ac017cdd246ce8bd547653d927e7bf77d7ee73d5/listener/listener.go#L498-L535)。

3. **不联动 Windows 系统代理。** 根据上述完整调用链，开关不会设置或清除 Windows 手动代理、PAC 或 WinHTTP 代理，也不会调用本地管理脚本。因此原本开启的系统代理不会因开启 TUN 而自动关闭，两者可能同时开启。这不表示 Windows 网络状态完全不变：mihomo 调用 sing-tun 创建接口，后者可按现有参数设置接口 DNS、添加路由，并在 `auto-route && strict-route` 时配置 WFP。[Windows 调用](https://github.com/MetaCubeX/mihomo/blob/ac017cdd246ce8bd547653d927e7bf77d7ee73d5/listener/sing_tun/server_windows.go#L12-L27)、[依赖版本 v0.4.22](https://github.com/MetaCubeX/mihomo/blob/ac017cdd246ce8bd547653d927e7bf77d7ee73d5/go.mod#L41)、[Windows 接口配置源码](https://github.com/MetaCubeX/sing-tun/blob/v0.4.22/tun_windows.go#L75-L191)。

4. **不提供跨内核重启持久化。** 刷新／重开面板会回读仍在运行的内核状态；重启 mihomo 则重新解析启动配置，再应用其中的 `tun`。例如文件为 `tun.enable: false`，面板临时开启后，按原文件重启会恢复关闭；重新加载该文件也会恢复其值。外部启动器若另行写配置或重放 API，则属于额外行为，不能归因于此开关。`profile.store-selected` 用于恢复策略组选择，不保存 TUN 开关。[启动解析](https://github.com/MetaCubeX/mihomo/blob/ac017cdd246ce8bd547653d927e7bf77d7ee73d5/hub/hub.go#L85-L105)、[读取配置文件](https://github.com/MetaCubeX/mihomo/blob/ac017cdd246ce8bd547653d927e7bf77d7ee73d5/hub/executor/executor.go#L50-L80)、[应用 TUN](https://github.com/MetaCubeX/mihomo/blob/ac017cdd246ce8bd547653d927e7bf77d7ee73d5/hub/executor/executor.go#L210-L212)、[重载路径](https://github.com/MetaCubeX/mihomo/blob/ac017cdd246ce8bd547653d927e7bf77d7ee73d5/hub/route/configs.go#L391-L439)、[store-selected](https://github.com/MetaCubeX/mihomo/blob/ac017cdd246ce8bd547653d927e7bf77d7ee73d5/hub/executor/executor.go#L439-L446)。

补充：该版本 `ReCreateTun` 创建失败时记录错误并把运行状态设回关闭，而 PATCH 处理仍返回无内容响应；不能仅凭 HTTP 成功认定 TUN 已启动，应看回读状态和内核日志。此结论来自上述启停及 PATCH 源码，未进行实际切换测试。
