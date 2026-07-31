import Foundation

enum DiagnosticLevel: String, Codable, Sendable {
  case info
  case warning
  case error
}

struct DiagnosticEvent: Codable, Identifiable, Sendable {
  let id: UUID
  let timestamp: Date
  let level: DiagnosticLevel
  let category: String
  let message: String

  init(level: DiagnosticLevel, category: String, message: String) {
    id = UUID()
    timestamp = Date()
    self.level = level
    self.category = category
    self.message = message
  }
}

final class DiagnosticLogStore: @unchecked Sendable {
  static let shared = DiagnosticLogStore()

  private let defaults: UserDefaults
  private let lock = NSLock()
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()
  private let maximumEventCount = 200

  init(defaults: UserDefaults? = UserDefaults(suiteName: AppConstants.appGroupIdentifier)) {
    self.defaults = defaults ?? .standard
  }

  func append(_ level: DiagnosticLevel, category: String, message: String) {
    lock.lock()
    defer { lock.unlock() }
    var stored = loadUnlocked()
    stored.append(DiagnosticEvent(level: level, category: category, message: message))
    if stored.count > maximumEventCount {
      stored.removeFirst(stored.count - maximumEventCount)
    }
    if let data = try? encoder.encode(stored) {
      defaults.set(data, forKey: AppConstants.diagnosticsStorageKey)
    }
  }

  func events() -> [DiagnosticEvent] {
    lock.lock()
    defer { lock.unlock() }
    return Array(loadUnlocked().reversed())
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    defaults.removeObject(forKey: AppConstants.diagnosticsStorageKey)
  }

  private func loadUnlocked() -> [DiagnosticEvent] {
    guard let data = defaults.data(forKey: AppConstants.diagnosticsStorageKey) else { return [] }
    return (try? decoder.decode([DiagnosticEvent].self, from: data)) ?? []
  }
}
