# V2BoxKit Android / Windows

这是 V2BoxKit 的 Android 与 Windows 共用客户端。Flutter 负责节点、订阅、
分流、测速、备份与自适应界面；Android 使用 `VpnService`，Windows 使用
Wintun，二者都通过固定版本 XTLS `libXray` 运行 Xray-core。

## 已实现

- Android 手机/平板与 Windows 自适应界面
- VLESS、VMess、Trojan、Shadowsocks、Hysteria2 分享链接和 Base64 订阅
- HTTPS 订阅、ETag/Last-Modified 条件更新和失败回滚
- 节点搜索、收藏、置顶、选择与真实代理延迟测试
- 全局、规则、直连三种模式
- 私有网络绕过、域名/IP 自定义规则、代理/直连/拦截动作
- 自定义 DNS、MTU，以及带认证的本机/局域网 SOCKS5 与 HTTP 分享
- JSON 配置备份/恢复和脱敏运行诊断
- Android 系统 VPN 授权、前台服务、TUN fd 注入与 socket protect
- Windows Wintun、自动系统路由、出口接口绑定与管理员启动

## 固定依赖

运行时固定为 `XTLS/libXray v26.7.28`，下载脚本校验 SHA-256。升级运行时必须
重新验证链接解析、TCP/UDP、DNS、网络切换和路由回滚。

## Android 构建

需要 Flutter 3.44+、JDK 21、Android SDK 36+ 和 NDK r29。

```bash
./tool/fetch_android_runtime.sh
flutter pub get
flutter test
flutter build apk --debug
```

生成文件位于：

```text
build/app/outputs/flutter-apk/app-debug.apk
```

首次连接必须由用户确认 Android VPN 授权。Android 8 及以上运行时显示前台
通知；Always-on VPN 由用户在系统 VPN 设置中配置。

## Windows 构建

需要 Windows 10/11、Flutter 3.44+ 和 Visual Studio 2022（Desktop
development with C++）。

```powershell
powershell -ExecutionPolicy Bypass -File tool\fetch_windows_runtime.ps1
flutter pub get
flutter test
flutter build windows
```

生成文件位于：

```text
build\windows\x64\runner\Release\
```

Windows 程序清单请求管理员权限，因为创建 Wintun 网卡、配置路由与 DNS
需要提升权限。`libXray.dll` 与 `wintun.dll` 必须和应用可执行文件一起分发。

## 目录

```text
lib/src/model/       共用数据模型
lib/src/services/    分享链接、订阅、备份、Xray 配置和平台桥
lib/src/state/       应用状态与连接流程
lib/src/ui/          自适应页面
android/             VpnService 与 gomobile AAR 接入
windows/             Wintun 与 libXray DLL 接入
tool/                固定版本运行时下载与校验
test/                解析、配置和模型测试
```

## 验证边界

Linux Devbox 可以完成 Dart 测试、静态检查和 Android APK 构建。以下验证仍需
对应平台：

- Android 真机首次授权、TCP/UDP、IPv4/IPv6、睡眠与 Wi-Fi/蜂窝切换
- Windows 10/11 管理员启动、Wintun 安装、默认路由和断开后的 DNS/路由恢复
- 有效自有节点的端到端流量、DNS 泄漏、内存和长时间稳定性

## 安全说明

- 应用不内置、不出售节点，只应连接有权使用的服务器。
- 节点凭证目前保存在平台应用存储中；正式版本应迁移到 Android Keystore /
  Windows Credential Locker。
- `.v2boxkit` 备份是明文 JSON，包含节点凭证。
- 局域网代理分享必须设置用户名和密码，且只应在可信网络启用。
- 发布前需补齐隐私政策、第三方许可、商店 VPN 声明和当地合规审核。
