# V2BoxKit

V2BoxKit 是一个面向 iPhone、iPad、Android 手机/平板和 Windows 的代理客户端
MVP。它包含节点导入、订阅拉取、节点管理、系统 VPN、分流和 Xray-core
运行链路。

| 平台 | 界面/系统隧道 | 状态 |
|---|---|---|
| iPhone / iPad | SwiftUI + `NEPacketTunnelProvider` | 源码完成，待 Xcode 与真机签名验证 |
| Android | Flutter + `VpnService` + libXray AAR | Debug APK 已在 Linux Devbox 构建 |
| Windows 10/11 x64 | Flutter + Wintun + libXray DLL | 源码完成，待 Windows/MSVC 构建与实机验证 |

## 当前能力

- iPhone / iPad 自适应界面（`NavigationSplitView`）
- 通过文本、剪贴板、二维码或 `v2boxkit://` 导入 VLESS、VMess、Trojan、Shadowsocks、Hysteria2
- 订阅持久化、单个/全部更新、条件请求和失败回滚；支持前台与系统后台刷新
- 节点分组、搜索、收藏、置顶、按名称/延迟排序
- 基于 libXray 本地 SOCKS 入站的真实代理延迟测试，并可自动选择最快节点
- 全局代理、规则分流、直连三种模式
- 自定义域名/IP 规则，支持代理、直连、拦截和优先级排序
- 自定义 UDP DNS、DNS over HTTPS、DNS over TLS 与隧道 MTU
- 公网出口、DNS、Xray 运行状态诊断；脱敏事件日志与一键重置
- 支持可选密码的 `.v2boxkit` 备份与恢复；密码备份使用 AES-GCM 和 PBKDF2-HMAC-SHA256
- 支持 iCloud 私有配置备份、手动恢复及配置变更后的自动上传
- 支持 Wi-Fi / 蜂窝按需连接和可信 Wi-Fi 排除
- 支持带用户名密码的本机或局域网 SOCKS5 / HTTP 代理分享
- 使用 Apple Network Extension 创建系统级 Packet Tunnel
- 使用官方 XTLS `libXray` 预编译 XCFramework 运行 Xray-core

## 环境要求

- macOS 与 Xcode 16+
- iOS / iPadOS 17+
- Apple Developer Program 账号
- Homebrew 与 XcodeGen

模拟器可以检查 UI 和解析逻辑，但 Packet Tunnel 必须在已签名的真机上验证。

Android 与 Windows 的环境、构建命令和验证边界见 [`clients/v2boxkit_client/README.md`](clients/v2boxkit_client/README.md)。

## 首次运行

```bash
brew install xcodegen
make bootstrap
open V2BoxKit.xcodeproj
```

`make bootstrap` 会下载固定版本 `v26.7.11` 的 `LibXray.xcframework`，然后生成 Xcode 工程。

在 Xcode 中还需要完成四项账号相关配置：

1. 将 `project.yml`、两个 entitlements 文件和 `AppConstants.swift` 中的 `com.example` 改成自己的反向域名。
2. 给 App 与 PacketTunnel 两个 Target 选择同一个 Team。
3. 在开发者后台为两个 App ID 启用 Network Extensions 和 App Groups，并确保描述文件包含 `packet-tunnel-provider`。
4. 为 App Target 启用 iCloud Key-value storage；不用 iCloud 功能时可关闭开关，但 entitlement 仍需与签名能力一致。

## 使用

1. 点击“添加链接”，粘贴一个或多个分享链接；或点击“订阅”，输入 HTTPS 订阅地址。
2. 从左侧节点列表选择节点。
3. 在设置中选择路由模式；规则模式可以配置直连域名。
4. 点击连接。首次连接时 iOS 会显示系统 VPN 配置授权框。
5. “设置 → 自动化与数据”中可以配置按需连接、本地代理分享和备份同步。

## 目录

```text
Sources/App/             SwiftUI 应用与状态管理
Sources/Shared/          App 和隧道扩展共用模型与 Xray 配置生成
Sources/PacketTunnel/    Network Extension 与 libXray 运行时
Tests/                   分享链接解析与配置生成测试
Config/                  Info.plist 和 entitlements
Scripts/                 固定版本依赖下载与校验
clients/v2boxkit_client/ Android / Windows 共用 Flutter 客户端与原生隧道接入
```

## GitHub Releases

- iOS / iPadOS、Android 和 Windows 使用独立版本标签与 Release。
- 标签格式分别为 `ios-vX.Y.Z`、`android-vX.Y.Z`、`windows-vX.Y.Z`。
- 下载地址：[GitHub Releases](https://github.com/joemwong/V2BoxKit/releases)。
- 签名与发布边界详见 [`RELEASING.md`](RELEASING.md)。

## 安全边界

- 订阅地址和节点凭证目前保存在 App Group `UserDefaults` 中，适合 MVP；正式产品应迁移到共享 Keychain，并对导出和日志做脱敏。
- 无密码文件备份是明文；iCloud 备份使用用户私有容器但不是应用层端到端密码加密。高敏感配置应使用带密码的文件备份。
- 局域网代理分享必须使用认证；仍应只在可信网络开启并定期更换密码。
- 应用不会内置或售卖节点。请只连接你有权使用的服务器，并遵守所在地区法律、App Store 规则和服务条款。
- `libXray` 上游声明 API 不保证稳定，因此依赖固定到 `v26.7.11`；升级时需要重新跑解析、连接、DNS 泄漏和网络切换测试。
- 当前不包含账号系统、WireGuard/SSH 客户端、网络聚合和商业化功能。

## 已知验证限制

本项目的代码生成和静态检查可以在 Linux 开发机执行，但 Xcode、iOS SDK、签名和 Network Extension 真机环境只存在于 macOS/Xcode。最终发布前至少要验证：

- Wi-Fi / 蜂窝网络切换与睡眠唤醒
- IPv4 / IPv6、TCP / UDP 和 DNS
- 订阅异常、节点失效、服务端域名解析
- 内存峰值、扩展被系统终止后的恢复
- App Store 隐私清单、出口合规与审核说明
