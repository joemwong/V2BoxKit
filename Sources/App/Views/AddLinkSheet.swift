import SwiftUI
import UIKit

struct AddLinkSheet: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var nodeStore: NodeStore

  @State private var text = ""
  @State private var errorMessage: String?
  @State private var scansQRCode = false

  var body: some View {
    NavigationStack {
      Form {
        Section("分享链接") {
          TextEditor(text: $text)
            .frame(minHeight: 180)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          HStack {
            Button("从剪贴板粘贴", systemImage: "doc.on.clipboard") {
              text = UIPasteboard.general.string ?? text
            }
            Spacer()
            Button("扫描二维码", systemImage: "qrcode.viewfinder") {
              scansQRCode = true
            }
          }
        } footer: {
          Text("每行一个链接，支持 VLESS、VMess、Trojan、Shadowsocks 和 Hysteria 2。")
        }
        if let errorMessage {
          Section {
            Text(errorMessage).foregroundStyle(.red)
          }
        }
      }
      .navigationTitle("添加链接")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("导入") { importLinks() }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
    .sheet(isPresented: $scansQRCode) {
      NavigationStack {
        QRScannerView { value in
          text = value
          scansQRCode = false
        }
        .ignoresSafeArea()
        .navigationTitle("扫描二维码")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("取消") { scansQRCode = false }
          }
        }
      }
    }
  }

  private func importLinks() {
    do {
      _ = try nodeStore.importPayload(text)
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
