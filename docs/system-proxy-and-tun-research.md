# Windows 系统代理与 TUN 同时开启调查

调查日期：2026-09-06。仅只读检查运行状态，没有开启 TUN 或修改代理配置。

## 本机证据

- Windows 注册表：ProxyEnable=1，ProxyServer=127.0.0.1:7890。
- GET http://127.0.0.1:9090/version：mihomo v1.19.30。
- GET /configs：rule 模式，mixed-port=7890，TUN 关闭，Mixed 栈，auto-route 和 auto-detect-interface 开启，DNS 劫持包含 UDP/TCP 53。
- official_config.yaml：fake-ip DNS；未显式配置 strict-route；edu.cn、私有域名/IP 和 Windows 连通性检测已有直连规则。
- scripts/windows/MihomoControl.psm1 的 Switch-MihomoLocalMode 拒绝双开状态。LocalSystemProxy 显式关闭 TUN；LocalTun 显式关闭系统代理。

## 判断

可以同时开启。系统代理是应用主动连接本机代理端口，TUN 是路由接管。正常情况下，浏览器连接本机代理端口，其他被路由接管的连接从 TUN 进入同一个 mihomo；不是同一请求必然经过两次远端代理。这是依据两类入站机制作出的判断，未实测双开。

相对只开系统代理，收益是覆盖不遵循系统代理的 TCP/UDP 应用，减少逐应用配置；代价是扩大 DNS 和路由影响范围，可能增加处理开销、VPN/虚拟网络兼容问题和排障复杂度。UDP 最终能否代理还取决于节点和规则。

相对只开 TUN，保留系统代理可让浏览器继续使用显式代理入口；TUN 单独失效而核心及 HTTP 入口正常时，浏览器可能继续可用，但这不是核心故障的冗余保护，也不保证更快。

系统代理 bypass 不等于 TUN 路由排除。已有直连规则降低校园网等目标误走远端节点的风险，但 DIRECT 连接仍可能先进入 mihomo，DNS 也可能发生变化。关闭系统代理后 TUN 仍可接管；关闭 TUN 后系统代理仍有效。

不能将双开理解为所有流量必经远端、绝不泄漏或双重加密。TUN 自动路由不等于 global 模式；当前依然按 rule 模式分流。Windows 局域网 DNS 劫持有官方已知限制；53 端口劫持也不等于接管应用自有 DoH。

建议：仅浏览器需求维持系统代理；长期需要广泛接管则单 TUN 更符合现有脚本；希望保留浏览器显式代理并临时补充其他程序覆盖时，双开合理，但 ToggleLocal 会拒绝切换，可显式指定已有目标状态恢复。

## 官方来源

- [mihomo TUN 文档](https://wiki.metacubex.one/config/inbound/tun/)：自动路由、Mixed 栈、DNS 劫持限制、Windows strict-route 行为；auto-redirect 仅 Linux 有效。
- [mihomo 代理端口](https://wiki.metacubex.one/config/inbound/port/)：HTTP/SOCKS 与 mixed 入口。
- [Chromium 网络设置](https://www.chromium.org/developers/design-documents/network-settings/)：浏览器使用系统代理及 bypass 语义。
- zashboard 开关的源码核实见同目录 zashboard-tun-toggle-research.md。
