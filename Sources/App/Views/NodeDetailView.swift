import SwiftUI

struct NodeDetailView: View {
  @EnvironmentObject private var nodeStore: NodeStore
  @EnvironmentObject private var tunnelManager: TunnelManager

  let node: ProxyNode
  @State private var errorMessage: String?

  var body: some View {
    ScrollView {
      VStack(spacing: 28) {
        connectionButton

        VStack(spacing: 12) {
          LabeledContent("状态", value: tunnelManager.statusText)
          LabeledContent("协议", value: node.kind.displayName)
          LabeledContent("服务器", value: node.endpoint)
          LabeledContent("路由", value: nodeStore.routing.mode.title)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))

        Text("节点凭证不会显示在界面中。系统首次连接时会请求添加 VPN 配置。")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: 560)
      .padding(24)
      .frame(maxWidth: .infinity)
    }
    .navigationTitle(node.name)
    .alert(
      "连接失败",
      isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )
    ) {
      Button("好", role: .cancel) {}
    } message: {
      Text(errorMessage ?? "未知错误")
    }
  }

  private var connectionButton: some View {
    Button {
      Task {
        do {
          try await tunnelManager.toggle(
            node: node,
            routing: nodeStore.routing,
            onDemand: nodeStore.settings.onDemand
          )
        } catch {
          errorMessage = error.localizedDescription
        }
      }
    } label: {
      VStack(spacing: 10) {
        Image(systemName: tunnelManager.isConnected ? "power.circle.fill" : "power.circle")
          .font(.system(size: 86, weight: .light))
        Text(tunnelManager.isConnected ? "断开连接" : "连接")
          .font(.headline)
        Text(tunnelManager.statusText)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .frame(width: 220, height: 220)
      .background(
        tunnelManager.isConnected ? Color.green.opacity(0.16) : Color.blue.opacity(0.12),
        in: Circle()
      )
    }
    .buttonStyle(.plain)
    .disabled(tunnelManager.isWorking)
    .accessibilityLabel(tunnelManager.isConnected ? "断开 VPN" : "连接 VPN")
  }
}
