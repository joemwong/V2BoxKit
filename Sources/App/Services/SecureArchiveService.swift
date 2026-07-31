import CryptoKit
import Foundation

actor SecureArchiveService {
  enum ArchiveError: LocalizedError {
    case invalidFile
    case passwordRequired
    case wrongPassword

    var errorDescription: String? {
      switch self {
      case .invalidFile: "配置备份文件无效"
      case .passwordRequired: "此备份需要密码"
      case .wrongPassword: "密码错误或备份已损坏"
      }
    }
  }

  private struct Envelope: Codable {
    let format: String
    let encrypted: Bool
    let iterations: Int?
    let salt: Data?
    let sealedPayload: Data?
    let payload: Data?
  }

  private let iterations = 120_000

  func encode(_ archive: ConfigurationArchive, password: String) async throws -> Data {
    let rounds = iterations
    return try await Task.detached(priority: .userInitiated) {
      try archive.validate()
      let archiveData = try JSONEncoder.archiveEncoder.encode(archive)
      guard !password.isEmpty else {
        return try JSONEncoder.archiveEncoder.encode(
          Envelope(
            format: "v2boxkit-archive-1",
            encrypted: false,
            iterations: nil,
            salt: nil,
            sealedPayload: nil,
            payload: archiveData
          )
        )
      }

      let salt = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
      let key = Self.deriveKey(password: password, salt: salt, iterations: rounds)
      let sealed = try AES.GCM.seal(archiveData, using: key)
      guard let combined = sealed.combined else { throw ArchiveError.invalidFile }
      return try JSONEncoder.archiveEncoder.encode(
        Envelope(
          format: "v2boxkit-archive-1",
          encrypted: true,
          iterations: rounds,
          salt: salt,
          sealedPayload: combined,
          payload: nil
        )
      )
    }.value
  }

  func requiresPassword(_ data: Data) throws -> Bool {
    let envelope = try Self.decodeEnvelope(data)
    return envelope.encrypted
  }

  func decode(_ data: Data, password: String) async throws -> ConfigurationArchive {
    try await Task.detached(priority: .userInitiated) {
      let envelope = try Self.decodeEnvelope(data)
      let archiveData: Data
      if envelope.encrypted {
        guard !password.isEmpty else { throw ArchiveError.passwordRequired }
        guard let salt = envelope.salt,
          let combined = envelope.sealedPayload,
          let rounds = envelope.iterations,
          (10_000...1_000_000).contains(rounds)
        else { throw ArchiveError.invalidFile }
        do {
          let key = Self.deriveKey(password: password, salt: salt, iterations: rounds)
          let sealed = try AES.GCM.SealedBox(combined: combined)
          archiveData = try AES.GCM.open(sealed, using: key)
        } catch {
          throw ArchiveError.wrongPassword
        }
      } else {
        guard let payload = envelope.payload else { throw ArchiveError.invalidFile }
        archiveData = payload
      }
      let archive = try JSONDecoder.archiveDecoder.decode(
        ConfigurationArchive.self, from: archiveData)
      try archive.validate()
      return archive
    }.value
  }

  private static func decodeEnvelope(_ data: Data) throws -> Envelope {
    guard let envelope = try? JSONDecoder.archiveDecoder.decode(Envelope.self, from: data),
      envelope.format == "v2boxkit-archive-1"
    else { throw ArchiveError.invalidFile }
    return envelope
  }

  private static func deriveKey(password: String, salt: Data, iterations: Int) -> SymmetricKey {
    let passwordKey = SymmetricKey(data: Data(password.utf8))
    var block = salt
    var index = UInt32(1).bigEndian
    withUnsafeBytes(of: &index) { block.append(contentsOf: $0) }

    var value = Data(HMAC<SHA256>.authenticationCode(for: block, using: passwordKey))
    var derived = value
    if iterations > 1 {
      for _ in 1..<iterations {
        value = Data(HMAC<SHA256>.authenticationCode(for: value, using: passwordKey))
        for index in derived.indices { derived[index] ^= value[index] }
      }
    }
    return SymmetricKey(data: derived)
  }
}

extension JSONEncoder {
  fileprivate static var archiveEncoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }
}

extension JSONDecoder {
  fileprivate static var archiveDecoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
