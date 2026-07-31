import SwiftUI

struct DiagnosticsView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var nodeStore: NodeStore
  @EnvironmentObject private var tunnelManager: TunnelManager
  @State private var checks: [DiagnosticCheck] = []
  @State private var events: [DiagnosticEvent] = []
  @State private var isRunning = false
  @State private var confirmsReset = false

  var body: some View {
    NavigationStack {
      List {
        Section("检查") {
          if checks.isEmpty {
            Text("点击“运行”检查公网出口、DNS 和隧道核心。")
              .foregroundStyle(.secondary)
          }
          ForEach(checks) { check in
            LabeledContent {
              Text(check.result).foregroundStyle(check.succeeded ? .secondary : .red)
            } label: {
              Label(
                check.name,
                systemImage: check.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill"
              )
              .foregroundStyle(check.succeeded ? .green : .red)
            }
          }
        }
        Section("最近日志") {
          ForEach(events) { event in
            VStack(alignment: .leading, spacing: 3) {
              HStack {
                Text(event.category).font(.caption.bold())
                Spacer()
                Text(event.timestamp, style: .time).font(.caption2).foregroundStyle(.secondary)
              }
              Text(event.message).font(.caption)
            }
          }
          if events.isEmpty { Text("暂无日志").foregroundStyle(.secondary) }
          Button("清空日志", role: .destructive) {
            DiagnosticLogStore.shared.clear()
            events = []
          }
        }
        Section("恢复") {
          Button("重置应用与 VPN 配置", role: .destructive) { confirmsReset = true }
        } footer: {
          Text("将删除本机节点、订阅、规则、日志和系统 VPN 配置，不影响订阅服务端数据。")
        }
      }
      .navigationTitle("网络诊断")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
        ToolbarItem(placement: .topBarTrailing) {
          Button("运行") { Task { await run() } }.disabled(isRunning)
        }
      }
      .onAppear { events = DiagnosticLogStore.shared.events() }
      .confirmationDialog("确认重置？", isPresented: $confirmsReset, titleVisibility: .visible) {
        Button("重置", role: .destructive) {
          Task {
            await tunnelManager.resetConfiguration()
            nodeStore.resetAllData()
            DiagnosticLogStore.shared.clear()
            checks = []
            events = []
          }
        }
      }
    }
  }

  @MainActor
  private func run() async {
    isRunning = true
    defer { isRunning = false }
    let url =
      URL(string: nodeStore.settings.publicIPCheckURL) ?? URL(string: "https://api.ipify.org")!
    checks = await NetworkDiagnosticsService().run(publicIPURL: url, tunnelManager: tunnelManager)
    for check in checks {
      DiagnosticLogStore.shared.append(
        check.succeeded ? .info : .warning,
        category: "diagnostic",
        message: "\(check.name)：\(check.result)"
      )
    }
    events = DiagnosticLogStore.shared.events()
  }
}
