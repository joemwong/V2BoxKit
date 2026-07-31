import SwiftUI

struct SubscriptionsView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var nodeStore: NodeStore
  @State private var showsAddSheet = false
  @State private var isRefreshingAll = false

  var body: some View {
    NavigationStack {
      List {
        ForEach(nodeStore.subscriptions) { subscription in
          VStack(alignment: .leading, spacing: 6) {
            HStack {
              Image(systemName: subscription.isPinned ? "pin.fill" : "arrow.triangle.2.circlepath")
              Text(subscription.name).font(.headline)
              Spacer()
              if nodeStore.refreshingSubscriptionIDs.contains(subscription.id) { ProgressView() }
            }
            Text(subscription.url.absoluteString)
              .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            HStack {
              Text(subscription.refreshInterval.title)
              if let date = subscription.lastUpdatedAt {
                Text("· \(date.formatted(date: .abbreviated, time: .shortened))")
              }
            }
            .font(.caption).foregroundStyle(.secondary)
            if let error = subscription.lastError {
              Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
            }
          }
          .padding(.vertical, 4)
          .swipeActions(edge: .leading) {
            Button("更新") {
              Task { _ = await nodeStore.refreshSubscription(id: subscription.id) }
            }.tint(.blue)
            Button(subscription.isPinned ? "取消置顶" : "置顶") {
              var edited = subscription
              edited.isPinned.toggle()
              nodeStore.updateSubscription(edited)
            }.tint(.orange)
          }
          .swipeActions(edge: .trailing) {
            Button("删除", role: .destructive) { nodeStore.removeSubscription(subscription) }
          }
          .contextMenu {
            Menu("更新频率") {
              ForEach(SubscriptionRefreshInterval.allCases) { interval in
                Button(interval.title) {
                  var edited = subscription
                  edited.refreshInterval = interval
                  nodeStore.updateSubscription(edited)
                }
              }
            }
          }
        }
      }
      .overlay {
        if nodeStore.subscriptions.isEmpty {
          ContentUnavailableView("还没有订阅", systemImage: "arrow.triangle.2.circlepath")
        }
      }
      .navigationTitle("订阅")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button("全部更新", systemImage: "arrow.clockwise") {
            isRefreshingAll = true
            Task {
              _ = await nodeStore.refreshAll()
              isRefreshingAll = false
            }
          }.disabled(isRefreshingAll || nodeStore.subscriptions.isEmpty)
          Button("添加", systemImage: "plus") { showsAddSheet = true }
        }
      }
      .sheet(isPresented: $showsAddSheet) { SubscriptionSheet() }
    }
  }
}
