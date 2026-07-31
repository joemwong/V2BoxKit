import SwiftUI

struct LocalSharingView: View {
  @EnvironmentObject private var nodeStore: NodeStore

  var body: some View {
    Form {
      Section("代理入口") {
        Toggle("启用本地分享", isOn: $nodeStore.routing.localSharing.isEnabled)
        Toggle("允许局域网设备访问", isOn: $nodeStore.routing.localSharing.allowLocalNetwork)
        TextField("SOCKS5 端口", value: $nodeStore.routing.localSharing.socksPort, format: .number)
          .keyboardType(.numberPad)
        TextField("HTTP 端口", value: $nodeStore.routing.localSharing.httpPort, format: .number)
          .keyboardType(.numberPad)
      }

      Section("认证") {
        TextField("用户名", text: $nodeStore.routing.localSharing.username)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        SecureField("密码", text: $nodeStore.routing.localSharing.password)
        Button("生成新密码", systemImage: "arrow.clockwise") {
          nodeStore.routing.localSharing.password = String(
            UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)
          ).lowercased()
        }
      }

      if !nodeStore.routing.localSharing.isValid {
        Section {
          Text("端口需为 1–65535 且不能相同；用户名和密码不能为空。")
            .foregroundStyle(.red)
        }
      }

      Section("连接信息") {
        LabeledContent("监听地址", value: nodeStore.routing.localSharing.listenAddress)
        if nodeStore.routing.localSharing.allowLocalNetwork {
          LabeledContent("Wi-Fi 地址", value: LocalNetworkAddressResolver.wiFiIPv4 ?? "未连接 Wi-Fi")
        }
        LabeledContent("SOCKS5", value: String(nodeStore.routing.localSharing.socksPort))
        LabeledContent("HTTP", value: String(nodeStore.routing.localSharing.httpPort))
      } footer: {
        Text("修改后重新连接 VPN 生效。允许局域网访问时，请只在可信网络使用并保留强密码。")
      }
    }
    .navigationTitle("本地代理分享")
  }
}
