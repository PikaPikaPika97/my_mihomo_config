# 代理控制

本上下文描述设备在本机或远端 mihomo 出口之间切换时使用的统一语言。

## Language

**目标代理状态（Target proxy state）**:
设备预期达到的完整代理运行状态，同时约束系统代理、mihomo TUN、代理出口和本机内核是否运行。
_Avoid_: 单项动作、脚本名

**本机系统代理状态（Local system-proxy state）**:
本机 mihomo 作为代理出口、系统代理开启且 TUN 关闭的目标代理状态。

**本机 TUN 状态（Local TUN state）**:
本机 mihomo 作为代理出口、TUN 开启且系统代理关闭的目标代理状态。

**直连状态（Direct state）**:
系统代理与 TUN 都关闭、但本机 mihomo 内核继续运行的目标代理状态。
_Avoid_: 关闭系统代理

**远端代理状态（Remote proxy state）**:
系统代理指向远端 mihomo 出口、本机 TUN 关闭且本机内核停止的低频目标代理状态。
_Avoid_: 工位模式

**停止状态（Stopped state）**:
系统代理关闭且本机 mihomo 内核停止的目标代理状态。
