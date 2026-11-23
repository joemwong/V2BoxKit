# Changelog

本文件记录 V2BoxKit 各客户端的重要变更。格式参考
[Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)；各平台使用独立版本标签
（`ios-vX.Y.Z`、`android-vX.Y.Z`、`windows-vX.Y.Z`），见 [`RELEASING.md`](RELEASING.md)。

## [Unreleased]

> 尚未在真机上验证。Android / Windows 改动尚未经 `flutter analyze` / `flutter test`
> 编译验证；iOS 改动已在 Swift 6 模式下通过类型检查（libXray 以桩代替）。

### Added

- **已连接时切换节点**（全部平台）：iOS 节点详情页显示“切换到此节点”；Android / Windows 点击节点即切换。
- **设置即时生效**（全部平台）：已连接时修改路由、DNS、本地分享设置会自动重连。iOS 在关闭设置页时生效，Android / Windows 在点击“保存设置”时生效。
- **iOS Xray DNS 配置**：生成 `dns` 块，未命中规则的域名经代理解析。DoT 服务器在 Xray 内部以 TCP DNS 发出（Xray-core 无 DoT 客户端），查询仍在代理隧道内。
- **域名规则前缀**（Android / Windows）：支持 `keyword:`、`geosite:`。
- **本地数据容错**（Android / Windows）：单条损坏的节点或订阅记录会被跳过；整体无法解析时把原始数据另存到 `v2boxkit.snapshot.v1.corrupt`。
- 回归测试：DNS 顺序与主机解析、出站标签、DNS 块、测速探针配置、域名规则大小写。

### Changed

- **“全部测速”并行化**（全部平台）：最多 4 个节点同时测试，端口预先统一分配，结束后只写一次存储。
- **Windows libXray 调用移到后台 isolate**，测速和连接时窗口不再卡死。
- **Android libXray 调用改为 4 线程池**，配合并行测速。
- Android 断开连接改由 VPN 服务事件驱动，6 秒兜底超时。
- iOS 测速的阻塞调用移出 Swift 协作线程池。
- Android / Windows 本地存储改用紧凑 JSON；备份文件保持缩进格式。
- iOS 节点分组按“手动导入”优先、自然排序显示。

### Fixed

- **Android / Windows 测速**使用完整隧道配置且未设置 `proxy`：Android 上全部显示失败，Windows 每次测速都会新建 Wintun 网卡并接管系统路由，直连/规则模式下还可能绕过节点。改为仅含本地 SOCKS 入站的探针配置。
- **iOS DNS 服务器顺序**被排序打乱，DoH/DoT 实际使用的不是第一个服务器。
- **iOS DoT 服务器名**遇到 IPv6 地址被截断（`2606:4700::1111` → `2606`）。
- **iOS UDP DNS 列表**只含 URL 时系统 DNS 为空，VPN 无法启动；现回退到引导 DNS。
- **iOS“绕过局域网”无效**：`includeAllNetworks` 下增加 `excludeLocalNetworks`。
- **iOS 出站标签顺序**：先移除托管的 `direct`/`block` 再命名节点出站。
- iOS 每次回到前台都会重写全部设置并触发 iCloud 上传。
- 订阅刷新期间被重命名或删除：iOS 使用旧分组名，Android / Windows 留下无法删除的孤儿节点。
- 重复添加订阅提示“订阅服务器返回失败”，现提示“该订阅地址已存在”。
- Android / Windows `regexp:` 规则被转小写（`\D` 变 `\d`），`keyword:`/`geosite:` 被包成 `domain:` 永不命中。
- “全部测速”期间连接会抛出未捕获异常。
- Android / Windows 并发刷新订阅时 busy 状态提前清除。
- Android VPN 服务停止与启动在不同线程交错，可能重复关闭或泄漏 TUN fd；`onDestroy` 不再在主线程执行阻塞 JNI 调用。
- Android 断开后立即重连，旧的 `stopSelf()` 可能销毁服务并静默拆掉新隧道；改用 `stopSelfResult(startId)`。
- Windows 切换时停止失败会一直卡在“断开中”。
- 一条损坏的本地记录导致 Android / Windows 加载空配置并在下次保存时覆盖用户数据。
- 恢复备份后路由页仍保留旧草稿，保存时覆盖已恢复的设置。

## 历史版本

`ios-v1.0.0`、`android-v1.0.0`、`windows-v1.0.0` – `windows-v1.0.3` 之前的变更见
[GitHub Releases](https://github.com/joemwong/V2BoxKit/releases) 与 git 历史。
