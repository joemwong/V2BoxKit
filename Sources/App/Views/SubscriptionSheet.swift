import SwiftUI

struct SubscriptionSheet: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var nodeStore: NodeStore

  @State private var name = ""
  @State private var urlText = ""
  @State private var refreshInterval: SubscriptionRefreshInterval = .daily
  @State private var isLoading = false
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      Form {
        Section("名称") {
          TextField("例如：机场订阅", text: $name)
        }
        Section("订阅地址") {
          TextField("https://example.com/subscription", text: $urlText)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        } footer: {
          Text("支持普通文本或 Base64 节点列表。更新失败时继续使用上一次成功的节点。")
        }
        Section("自动更新") {
          Picker("频率", selection: $refreshInterval) {
            ForEach(SubscriptionRefreshInterval.allCases) { interval in
              Text(interval.title).tag(interval)
            }
          }
        }
        if isLoading {
          Section { ProgressView("正在更新订阅…") }
        }
        if let errorMessage {
          Section { Text(errorMessage).foregroundStyle(.red) }
        }
      }
      .navigationTitle("添加订阅")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("添加") { Task { await add() } }
            .disabled(
              isLoading || URL(string: urlText) == nil
                || name.trimmingCharacters(in: .whitespaces).isEmpty
            )
        }
      }
    }
  }

  @MainActor
  private func add() async {
    guard let url = URL(string: urlText) else { return }
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }
    do {
      try await nodeStore.addSubscription(
        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
        url: url,
        refreshInterval: refreshInterval
      )
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
