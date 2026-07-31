import Foundation

struct CloudSyncService: Sendable {
  enum SyncError: LocalizedError {
    case archiveTooLarge
    case noBackup
    case invalidBackup

    var errorDescription: String? {
      switch self {
      case .archiveTooLarge: "配置超过 iCloud 轻量同步容量，请改用文件备份"
      case .noBackup: "iCloud 中还没有配置备份"
      case .invalidBackup: "iCloud 配置备份无法解析"
      }
    }
  }

  private static let archiveKey = "configurationArchive.v1"
  private static let maximumSize = 900_000

  func upload(_ archive: ConfigurationArchive) throws {
    let data = try JSONEncoder().encode(archive)
    guard data.count <= Self.maximumSize else { throw SyncError.archiveTooLarge }
    let store = NSUbiquitousKeyValueStore.default
    store.set(data, forKey: Self.archiveKey)
    store.synchronize()
  }

  func download() throws -> ConfigurationArchive {
    let store = NSUbiquitousKeyValueStore.default
    store.synchronize()
    guard let data = store.data(forKey: Self.archiveKey) else { throw SyncError.noBackup }
    guard let archive = try? JSONDecoder().decode(ConfigurationArchive.self, from: data) else {
      throw SyncError.invalidBackup
    }
    try archive.validate()
    return archive
  }
}
