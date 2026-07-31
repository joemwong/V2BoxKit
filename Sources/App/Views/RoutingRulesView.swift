import SwiftUI

struct RoutingRulesView: View {
  @EnvironmentObject private var nodeStore: NodeStore
  @State private var editingRule: RoutingRule?

  var body: some View {
    List {
      ForEach($nodeStore.routing.customRules) { $rule in
        Button {
          editingRule = rule
        } label: {
          HStack {
            VStack(alignment: .leading) {
              Text(rule.name)
              Text("\(rule.kind.title) · \(rule.action.title) · \(rule.normalizedValues.count) 条")
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $rule.isEnabled).labelsHidden()
          }
        }
        .buttonStyle(.plain)
      }
      .onDelete { nodeStore.routing.customRules.remove(atOffsets: $0) }
      .onMove { nodeStore.routing.customRules.move(fromOffsets: $0, toOffset: $1) }
    }
    .navigationTitle("自定义规则")
    .toolbar {
      EditButton()
      Button("添加", systemImage: "plus") {
        editingRule = RoutingRule(name: "新规则", kind: .domain, action: .proxy)
      }
    }
    .sheet(item: $editingRule) { rule in
      RoutingRuleEditor(rule: rule) { saved in
        if let index = nodeStore.routing.customRules.firstIndex(where: { $0.id == saved.id }) {
          nodeStore.routing.customRules[index] = saved
        } else {
          nodeStore.routing.customRules.append(saved)
        }
      }
    }
  }
}

private struct RoutingRuleEditor: View {
  @Environment(\.dismiss) private var dismiss
  @State var rule: RoutingRule
  let onSave: (RoutingRule) -> Void

  var body: some View {
    NavigationStack {
      Form {
        TextField("规则名称", text: $rule.name)
        Picker("类型", selection: $rule.kind) {
          ForEach(RoutingRuleKind.allCases) { kind in Text(kind.title).tag(kind) }
        }
        Picker("动作", selection: $rule.action) {
          ForEach(RoutingRuleAction.allCases) { action in Text(action.title).tag(action) }
        }
        TextEditor(text: valuesBinding)
          .frame(minHeight: 160)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
      }
      .navigationTitle("编辑规则")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            onSave(rule)
            dismiss()
          }.disabled(rule.name.isEmpty || rule.normalizedValues.isEmpty)
        }
      }
    }
  }

  private var valuesBinding: Binding<String> {
    Binding(
      get: { rule.values.joined(separator: "\n") },
      set: { rule.values = $0.components(separatedBy: .newlines) }
    )
  }
}
