import SwiftUI
import UniformTypeIdentifiers

struct BackupView: View {
  @EnvironmentObject private var nodeStore: NodeStore
  @State private var exportPassword = ""
  @State private var importPassword = ""
  @State private var exportDocument: BackupDocument?
  @State private var pendingImportData: Data?
  @State private var isExporting = false
  @State private var isImporting = false
  @State private var isWorking = false
  @State private var message: String?
  @State private var confirmsCloudRestore = false
  private let archiveService = SecureArchiveService()

  var body: some View {
    Form {
      Section("文件备份") {
        SecureField("导出密码（可留空）", text: $exportPassword)
        Button("导出 .v2boxkit 备份", systemImage: "square.and.arrow.up") {
          Task { await prepareExport() }
        }
        .disabled(isWorking)
      } footer: {
        Text("设置密码后使用 AES-GCM 加密；请妥善保存密码，应用无法找回。")
      }

      Section("文件恢复") {
        Button("选择备份文件", systemImage: "square.and.arrow.down") {
          isImporting = true
        }
        if pendingImportData != nil {
          SecureField("备份密码", text: $importPassword)
          Button("校验并恢复") { Task { await restorePendingImport() } }
            .disabled(isWorking)
        }
      } footer: {
        Text("恢复会替换当前节点、订阅、路由和应用设置。建议先导出当前配置。")
      }

      Section("iCloud") {
        Toggle("配置变更后自动备份", isOn: $nodeStore.settings.iCloudSyncEnabled)
        Button("立即备份到 iCloud", systemImage: "icloud.and.arrow.up") {
          perform { try nodeStore.uploadConfigurationToCloud() }
        }
        Button("从 iCloud 恢复", systemImage: "icloud.and.arrow.down") {
          confirmsCloudRestore = true
        }
      } footer: {
        Text("使用当前 Apple ID 的私有键值存储；超过容量时请改用文件备份。冲突时以手动恢复或最后上传的版本为准。")
      }

      if let message {
        Section { Text(message).foregroundStyle(message.hasPrefix("失败") ? .red : .secondary) }
      }
    }
    .navigationTitle("备份与同步")
    .fileExporter(
      isPresented: $isExporting,
      document: exportDocument,
      contentType: .data,
      defaultFilename: "V2BoxKit-Backup.v2boxkit"
    ) { result in
      if case .failure(let error) = result { message = "失败：\(error.localizedDescription)" }
    }
    .fileImporter(isPresented: $isImporting, allowedContentTypes: [.data]) { result in
      handleImportedURL(result)
    }
    .confirmationDialog("从 iCloud 恢复会替换当前配置", isPresented: $confirmsCloudRestore) {
      Button("恢复", role: .destructive) {
        perform { try nodeStore.restoreConfigurationFromCloud() }
      }
    }
  }

  @MainActor
  private func prepareExport() async {
    isWorking = true
    defer { isWorking = false }
    do {
      let data = try await archiveService.encode(
        nodeStore.makeConfigurationArchive(),
        password: exportPassword
      )
      exportDocument = BackupDocument(data: data)
      isExporting = true
      message = "备份已生成"
    } catch {
      message = "失败：\(error.localizedDescription)"
    }
  }

  private func handleImportedURL(_ result: Result<URL, Error>) {
    do {
      let url = try result.get()
      let didAccess = url.startAccessingSecurityScopedResource()
      defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
      pendingImportData = try Data(contentsOf: url)
      importPassword = ""
      message = "备份已读取，请输入密码（未加密备份可留空）"
    } catch {
      message = "失败：\(error.localizedDescription)"
    }
  }

  @MainActor
  private func restorePendingImport() async {
    guard let pendingImportData else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      let archive = try await archiveService.decode(pendingImportData, password: importPassword)
      try nodeStore.restoreConfigurationArchive(archive)
      self.pendingImportData = nil
      importPassword = ""
      message = "配置恢复成功"
    } catch {
      message = "失败：\(error.localizedDescription)"
    }
  }

  private func perform(_ action: () throws -> Void) {
    do {
      try action()
      message = "操作成功"
    } catch {
      message = "失败：\(error.localizedDescription)"
    }
  }
}
