import SwiftUI

struct ContentView: View {
  private enum PresentedSheet: String, Identifiable {
    case addLink
    case subscriptions
    case settings
    case diagnostics

    var id: String { rawValue }
  }

  @EnvironmentObject private var nodeStore: NodeStore
  @State private var presentedSheet: PresentedSheet?
  @State private var searchText = ""
  @State private var importMessage: String?

  private var groupedNodes: [(String, [ProxyNode])] {
    let groups = Dictionary(
      grouping: nodeStore.visibleNodes(searchText: searchText), by: \.groupName)
    return groups.keys.sorted().map { ($0, groups[$0] ?? []) }
  }

  var body: some View {
    NavigationSplitView {
      List(selection: $nodeStore.selectedNodeID) {
        ForEach(groupedNodes, id: \.0) { group, nodes in
          Section(group) {
            ForEach(nodes) { node in
              NodeRow(node: node)
                .tag(node.id)
                .contextMenu {
                  Button(node.isFavorite ? "取消收藏" : "收藏", systemImage: "star") {
                    nodeStore.toggleFavorite(node)
                  }
                  Button(node.isPinned ? "取消置顶" : "置顶", systemImage: "pin") {
                    nodeStore.togglePinned(node)
                  }
                  Button("测试延迟", systemImage: "speedometer") {
                    Task { await nodeStore.measureLatency(for: node) }
                  }
                  Button("删除", role: .destructive) { nodeStore.remove(node) }
                }
            }
          }
        }
      }
      .searchable(text: $searchText, prompt: "搜索名称、地址或分组")
      .overlay {
        if groupedNodes.isEmpty {
          ContentUnavailableView(
            nodeStore.nodes.isEmpty ? "还没有节点" : "没有匹配节点",
            systemImage: "point.3.connected.trianglepath.dotted",
            description: Text(nodeStore.nodes.isEmpty ? "导入分享链接或订阅后即可连接" : "调整搜索或收藏筛选")
          )
        }
      }
      .navigationTitle("V2BoxKit")
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button("全部测速", systemImage: "speedometer") {
            Task { await nodeStore.measureAllLatencies() }
          }
          .disabled(nodeStore.nodes.isEmpty || !nodeStore.pingingNodeIDs.isEmpty)
          Menu {
            Button("添加链接", systemImage: "link.badge.plus") {
              presentedSheet = .addLink
            }
            Button("管理订阅", systemImage: "arrow.triangle.2.circlepath") {
              presentedSheet = .subscriptions
            }
          } label: {
            Image(systemName: "plus")
          }
          Menu {
            Button("订阅", systemImage: "arrow.triangle.2.circlepath") {
              presentedSheet = .subscriptions
            }
            Button("网络诊断", systemImage: "stethoscope") {
              presentedSheet = .diagnostics
            }
            Button("设置", systemImage: "gearshape") {
              presentedSheet = .settings
            }
          } label: {
            Image(systemName: "ellipsis.circle")
          }
        }
      }
    } detail: {
      if let node = nodeStore.selectedNode {
        NodeDetailView(node: node)
      } else {
        ContentUnavailableView("请选择节点", systemImage: "server.rack")
      }
    }
    .sheet(item: $presentedSheet) { sheet in
      switch sheet {
      case .addLink:
        AddLinkSheet()
      case .subscriptions:
        SubscriptionsView()
      case .settings:
        SettingsView()
      case .diagnostics:
        DiagnosticsView()
      }
    }
    .onOpenURL { url in
      guard let payload = DeepLinkImporter.payload(from: url) else { return }
      do {
        let count = try nodeStore.importPayload(payload)
        importMessage = "已导入 \(count) 个节点"
      } catch {
        importMessage = error.localizedDescription
      }
    }
    .alert(
      "URL 导入",
      isPresented: Binding(
        get: { importMessage != nil },
        set: { if !$0 { importMessage = nil } }
      )
    ) {
      Button("好") { importMessage = nil }
    } message: {
      Text(importMessage ?? "")
    }
  }
}

private struct NodeRow: View {
  @EnvironmentObject private var nodeStore: NodeStore
  let node: ProxyNode

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: node.isFavorite ? "star.fill" : "network")
        .foregroundStyle(.blue)
        .frame(width: 28, height: 28)
        .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
      VStack(alignment: .leading, spacing: 3) {
        HStack {
          if node.isPinned { Image(systemName: "pin.fill").font(.caption2) }
          Text(node.name).lineLimit(1)
        }
        Text("\(node.kind.displayName) · \(node.endpoint)")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer()
      if nodeStore.pingingNodeIDs.contains(node.id) {
        ProgressView().controlSize(.small)
      } else {
        Text(node.latencyText)
          .font(.caption.monospacedDigit())
          .foregroundStyle((node.latencyMilliseconds ?? 10_000) < 1_000 ? .green : .secondary)
      }
    }
    .padding(.vertical, 3)
  }
}
