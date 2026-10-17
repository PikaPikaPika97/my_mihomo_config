# 系统代理开启时使用 zashboard 的调查

核查日期：2026-09-06。来源限官方项目文档、源码和 Chrome 官方说明。没有执行配置变更。

## 本机结论

主代理实测：Windows 系统代理 `127.0.0.1:7890` 已开启；mihomo API 报告 `mode=rule`、`tun.enable=false`、`allow-lan=false`，版本 v1.19.30。`http://127.0.0.1:9090/ui/` 返回 200，标题为 zashboard。磁盘配置已经设置 `external-controller: 127.0.0.1:9090`、`external-ui: ui`、`profile.store-selected: true`。

因此直接使用现有本地面板最合适，无需新装面板、另开服务或关闭系统代理。

## 优点

- 可以查看节点、连接、流量与日志，并通过 API 切换策略组和运行模式，排查请求走了哪个规则或节点。API 还支持关闭连接、健康检查和集合更新。[mihomo API](https://wiki.metacubex.one/api/)
- 面板是控制界面，代理仍由已有 mihomo 内核承担；按其架构推断，打开网页不会建立第二层代理，也不会自动提升网速，关闭网页不等于关闭内核。[zashboard HTTP 请求源码](https://github.com/Zephyruso/zashboard/blob/main/src/api/http.ts)
- 本地静态页面由现有 API 的 `/ui` 提供，不增加独立服务器进程；页面与 API 同协议、主机和端口，可避免跨源连接问题。安装完整字体版或无字体版还可避免 CDN 字体加载依赖。[mihomo 全局配置](https://wiki.metacubex.one/config/general/)、[zashboard README](https://github.com/Zephyruso/zashboard/blob/main/README.md)

## 成本和注意事项

- 常开页面需要浏览器内存、图表渲染和状态通信；节点多、连接多、持续看日志时更明显。官方未提供可用于本机的量化性能数据，不能承诺具体 MB 或 CPU 百分比。测速和集合更新还会主动产生网络请求。[mihomo API](https://wiki.metacubex.one/api/)
- 页面设置与核心设置不是同一层。zashboard 后端列表和偏好使用浏览器 localStorage；换浏览器、换站点地址或清理站点数据可能丢失这些记录。核心策略组选择是否跨重启保留由 `profile.store-selected` 控制，本机已开启。不能把所有面板运行时调整都视为已写回 YAML。[后端存储源码](https://github.com/Zephyruso/zashboard/blob/main/src/store/setup.ts)、[存储助手源码](https://github.com/Zephyruso/zashboard/blob/main/src/helper/storage.ts)、[mihomo 缓存配置](https://wiki.metacubex.one/config/general/#缓存)
- 本机 API 可无认证读取，脚本的 ApiSecret 为空，但控制器只监听回环地址，当前没有因面板而开放到局域网。控制 API 具有更改配置等权限，不应为本机浏览器面板改为监听所有接口。若日后开放其他设备访问，需另外考虑访问密钥和网络访问限制。`allow-lan` 控制代理端口的局域网访问，不等于 API 监听限制。[mihomo 全局配置](https://wiki.metacubex.one/config/general/)
- 现有脚本统筹系统代理与 TUN。应继续通过脚本切换工作方式；直接在面板单独打开 TUN 可能产生系统代理和 TUN 同时开启的混合状态，现有 ToggleLocal 会拒绝这种状态。此点由主代理对本机脚本的调查提供，非 zashboard 通用故障。
- 面板展示的是进入 mihomo 的连接和流量。当前使用系统代理，绕过系统代理或不遵循系统代理的应用流量不一定进入内核，因此不能把面板统计当作全机网络统计。此点为根据本机流量接入方式作出的判断。
- 本机面板更新地址经 `ghfast.top` 转发 GitHub 下载，意味着更新链路还依赖该第三方。zashboard 官方提示，面板自动更新依赖正确的核心 UI 下载地址，否则可能更新成核心默认面板。[zashboard README](https://github.com/Zephyruso/zashboard/blob/main/README.md)

## 为什么不优先使用在线面板

在线版免维护静态文件，但网页加载依赖外网站点、DNS 和当前网络，页面代码也随托管方更新；本地版对当前配置更可靠、便于故障排查。这是根据部署与请求架构作出的取舍判断，不代表发现在线站点恶意行为。

在线页面访问本地 API 时需要额外考虑 CORS、本地网络访问授权和 HTTP/HTTPS 兼容性。不能笼统说“HTTPS 一定连不上本地 HTTP”：Chrome 官方说明自 142 推出 Local Network Access 授权，替代早先 PNA 方案，某些已知本地地址请求可获混合内容豁免；浏览器、地址形式、请求类型的差异仍会影响结果。设置 mihomo 的 `allow-private-network` 不等于绕过浏览器授权。本机现成的同源 `/ui/` 路径可避免这类跨站复杂性。[Chrome 官方 LNA 说明](https://developer.chrome.com/blog/local-network-access)、[mihomo CORS 配置](https://wiki.metacubex.one/config/general/#外部控制-api)
