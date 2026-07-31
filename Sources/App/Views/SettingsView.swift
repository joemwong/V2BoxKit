import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var nodeStore: NodeStore

  var body: some View {
    NavigationStack {
      Form {
        Section("节点") {
          Picker("排序", selection: $nodeStore.settings.nodeSortMode) {
            ForEach(NodeSortMode.allCases) { mode in Text(mode.title).tag(mode) }
          }
          Toggle("仅显示收藏", isOn: $nodeStore.settings.showFavoritesOnly)
          Toggle("测速后自动选择最快节点", isOn: $nodeStore.settings.autoSelectFastest)
        }

        Section("自动化与数据") {
          NavigationLink("按需连接") {
            OnDemandSettingsView()
          }
          NavigationLink("本地 SOCKS5 / HTTP 分享") {
            LocalSharingView()
          }
          NavigationLink("备份与 iCloud 同步") {
            BackupView()
          }
        }

        Section("路由模式") {
          Picker("模式", selection: $nodeStore.routing.mode) {
            ForEach(RoutingMode.allCases) { mode in Text(mode.title).tag(mode) }
          }
          .pickerStyle(.segmented)
        }

        if nodeStore.routing.mode == .rule {
          Section("规则") {
            Toggle("绕过局域网和私有地址", isOn: $nodeStore.routing.bypassPrivateNetworks)
            NavigationLink("自定义规则（\(nodeStore.routing.customRules.count)）") {
              RoutingRulesView()
            }
            TextEditor(text: directDomainsBinding)
              .frame(minHeight: 100)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
          } footer: {
            Text("上方自定义规则优先匹配；文本框每行一个需要直连的域名。")
          }
        }

        Section("DNS") {
          Picker("协议", selection: $nodeStore.routing.dns.mode) {
            ForEach(DNSMode.allCases) { mode in Text(mode.title).tag(mode) }
          }
          TextField(
            nodeStore.routing.dns.mode == .doh ? "https://1.1.1.1/dns-query" : "1.1.1.1",
            text: dnsServersBinding,
            axis: .vertical
          )
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          if nodeStore.routing.dns.mode != .udp {
            TextField("引导 DNS，例如 1.1.1.1", text: $nodeStore.routing.dns.fallbackServer)
              .keyboardType(.numbersAndPunctuation)
          }
        } footer: {
          Text("DoH/DoT 由 iOS 隧道 DNS 设置加密；引导 DNS 仅用于解析加密 DNS 主机名。")
        }

        Section("隧道") {
          Stepper(
            "MTU：\(nodeStore.routing.mtu)", value: $nodeStore.routing.mtu, in: 1280...9000, step: 10
          )
          TextField("公网 IP 检查地址", text: $nodeStore.settings.publicIPCheckURL)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
        }

        Section("说明") {
          LabeledContent("核心", value: "Xray TUN")
          LabeledContent("最低系统", value: "iOS / iPadOS 17")
        }
      }
      .navigationTitle("设置")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("完成") { dismiss() }
        }
      }
    }
  }

  private var directDomainsBinding: Binding<String> {
    Binding(
      get: { nodeStore.routing.directDomains.joined(separator: "\n") },
      set: { nodeStore.routing.directDomains = $0.components(separatedBy: .newlines) }
    )
  }

  private var dnsServersBinding: Binding<String> {
    Binding(
      get: { nodeStore.routing.dns.servers.joined(separator: "\n") },
      set: { nodeStore.routing.dns.servers = $0.components(separatedBy: .newlines) }
    )
  }
}
