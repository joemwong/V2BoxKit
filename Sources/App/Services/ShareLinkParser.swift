import Foundation

enum ShareLinkParser {
  enum ParserError: LocalizedError {
    case unsupportedScheme
    case malformedLink
    case noValidNodes

    var errorDescription: String? {
      switch self {
      case .unsupportedScheme: "暂不支持这个分享链接协议"
      case .malformedLink: "分享链接格式不完整"
      case .noValidNodes: "没有找到可用的节点链接"
      }
    }
  }

  private static let supportedPrefixes = [
    "vless://", "vmess://", "trojan://", "ss://", "hysteria2://", "hy2://",
  ]

  static func parseMany(_ text: String) throws -> [ProxyNode] {
    let normalized = decodeSubscriptionIfNeeded(text)
    let candidates =
      normalized
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { line in supportedPrefixes.contains { line.lowercased().hasPrefix($0) } }

    let nodes = candidates.compactMap { try? parse($0) }
    guard !nodes.isEmpty else { throw ParserError.noValidNodes }
    return nodes
  }

  static func parse(_ rawValue: String) throws -> ProxyNode {
    let rawURI = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let scheme = rawURI.prefix { $0 != ":" }.lowercased()

    switch scheme {
    case "vmess":
      return try parseVMess(rawURI)
    case "vless":
      return try parseURLBased(rawURI, kind: .vless)
    case "trojan":
      return try parseURLBased(rawURI, kind: .trojan)
    case "ss":
      return try parseShadowsocks(rawURI)
    case "hysteria2", "hy2":
      return try parseURLBased(rawURI, kind: .hysteria2)
    default:
      throw ParserError.unsupportedScheme
    }
  }

  private static func parseVMess(_ rawURI: String) throws -> ProxyNode {
    let payload = String(rawURI.dropFirst("vmess://".count))
    if let data = decodeBase64(payload),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let host = stringValue(object["add"]),
      let port = intValue(object["port"])
    {
      let name = stringValue(object["ps"])?.nilIfEmpty ?? host
      return ProxyNode(name: name, kind: .vmess, host: host, port: port, rawURI: rawURI)
    }
    return try parseURLBased(rawURI, kind: .vmess)
  }

  private static func parseShadowsocks(_ rawURI: String) throws -> ProxyNode {
    if let node = try? parseURLBased(rawURI, kind: .shadowsocks) {
      return node
    }

    let payload = String(rawURI.dropFirst("ss://".count)).components(separatedBy: "#")[0]
    guard let data = decodeBase64(payload),
      let decoded = String(data: data, encoding: .utf8),
      let at = decoded.lastIndex(of: "@"),
      let colon = decoded[decoded.index(after: at)...].lastIndex(of: ":"),
      let port = Int(decoded[decoded.index(after: colon)...])
    else {
      throw ParserError.malformedLink
    }
    let host = String(decoded[decoded.index(after: at)..<colon])
    let name = fragmentName(rawURI) ?? host
    return ProxyNode(name: name, kind: .shadowsocks, host: host, port: port, rawURI: rawURI)
  }

  private static func parseURLBased(_ rawURI: String, kind: ProxyProtocol) throws -> ProxyNode {
    guard let components = URLComponents(string: rawURI),
      let host = components.host?.nilIfEmpty,
      let port = components.port,
      (1...65_535).contains(port)
    else {
      throw ParserError.malformedLink
    }
    let name = components.fragment?.removingPercentEncoding?.nilIfEmpty ?? host
    return ProxyNode(name: name, kind: kind, host: host, port: port, rawURI: rawURI)
  }

  private static func decodeSubscriptionIfNeeded(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if supportedPrefixes.contains(where: { trimmed.lowercased().contains($0) }) {
      return trimmed
    }
    guard let data = decodeBase64(trimmed),
      let decoded = String(data: data, encoding: .utf8)
    else {
      return trimmed
    }
    return decoded
  }

  private static func decodeBase64(_ value: String) -> Data? {
    let withoutFragment = value.components(separatedBy: "#")[0]
    var normalized =
      withoutFragment
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
      .filter { !$0.isWhitespace }
    let remainder = normalized.count % 4
    if remainder != 0 { normalized += String(repeating: "=", count: 4 - remainder) }
    return Data(base64Encoded: normalized)
  }

  private static func fragmentName(_ value: String) -> String? {
    URLComponents(string: value)?.fragment?.removingPercentEncoding?.nilIfEmpty
  }

  private static func stringValue(_ value: Any?) -> String? {
    switch value {
    case let value as String: value
    case let value as NSNumber: value.stringValue
    default: nil
    }
  }

  private static func intValue(_ value: Any?) -> Int? {
    if let value = value as? Int { return value }
    if let value = value as? NSNumber { return value.intValue }
    if let value = value as? String { return Int(value) }
    return nil
  }
}

extension String {
  fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
