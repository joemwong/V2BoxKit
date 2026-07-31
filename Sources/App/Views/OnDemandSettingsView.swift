import SwiftUI

struct OnDemandSettingsView: View {
  @EnvironmentObject private var nodeStore: NodeStore
  @EnvironmentObject private var tunnelManager: TunnelManager
  @State private var message: String?
  @State private var isApplying = false

  var body: some View {
    Form {
      Section("触发条件") {
        Toggle("启用按需连接", isOn: $nodeStore.settings.onDemand.isEnabled)
        Toggle("连接 Wi-Fi 时启用", isOn: $nodeStore.settings.onDemand.connectOnWiFi)
        Toggle("使用蜂窝网络时启用", isOn: $nodeStore.settings.onDemand.connectOnCellular)
      }

      Section("可信 Wi-Fi") {
        TextEditor(text: excludedSSIDsBinding)
          .frame(minHeight: 120)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
      } footer: {
        Text("每行一个 SSID。连接这些 Wi-Fi 时优先断开 VPN。")
      }

      Section {
        Button("应用到系统 VPN 配置") {
          Task { await apply() }
        }
        .disabled(isApplying)
        if let message {
          Text(message).foregroundStyle(message.hasPrefix("失败") ? .red : .secondary)
        }
      } footer: {
        Text("首次使用需先手动连接一次，以创建系统 VPN 配置。iOS 会在网络类型变化时执行规则。")
      }
    }
    .navigationTitle("按需连接")
  }

  private var excludedSSIDsBinding: Binding<String> {
    Binding(
      get: { nodeStore.settings.onDemand.excludedWiFiSSIDs.joined(separator: "\n") },
      set: { nodeStore.settings.onDemand.excludedWiFiSSIDs = $0.components(separatedBy: .newlines) }
    )
  }

  @MainActor
  private func apply() async {
    isApplying = true
    defer { isApplying = false }
    do {
      try await tunnelManager.configureOnDemand(nodeStore.settings.onDemand)
      message = "系统按需规则已更新"
    } catch {
      message = "失败：\(error.localizedDescription)"
    }
  }
}
