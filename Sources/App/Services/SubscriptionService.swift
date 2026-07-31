import Foundation

struct SubscriptionFetchResult: Sendable {
  let nodes: [ProxyNode]?
  let etag: String?
  let lastModified: String?

  var isNotModified: Bool { nodes == nil }
}

struct SubscriptionService {
  enum SubscriptionError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unsupportedEncoding

    var errorDescription: String? {
      switch self {
      case .invalidURL: "订阅地址必须是 HTTPS URL"
      case .invalidResponse: "订阅服务器返回失败"
      case .unsupportedEncoding: "订阅内容不是 UTF-8 文本"
      }
    }
  }

  func fetchNodes(from url: URL) async throws -> [ProxyNode] {
    let subscription = ProxySubscription(name: url.host ?? "订阅", url: url)
    return try await fetch(subscription: subscription).nodes ?? []
  }

  func fetch(subscription: ProxySubscription) async throws -> SubscriptionFetchResult {
    guard subscription.url.scheme?.lowercased() == "https" else {
      throw SubscriptionError.invalidURL
    }

    var request = URLRequest(url: subscription.url)
    request.timeoutInterval = 20
    request.setValue("V2BoxKit/1.0", forHTTPHeaderField: "User-Agent")
    if let etag = subscription.etag {
      request.setValue(etag, forHTTPHeaderField: "If-None-Match")
    }
    if let lastModified = subscription.lastModified {
      request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
    }
    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw SubscriptionError.invalidResponse
    }
    if httpResponse.statusCode == 304 {
      return SubscriptionFetchResult(
        nodes: nil,
        etag: httpResponse.value(forHTTPHeaderField: "ETag") ?? subscription.etag,
        lastModified: httpResponse.value(forHTTPHeaderField: "Last-Modified")
          ?? subscription.lastModified
      )
    }
    guard (200..<300).contains(httpResponse.statusCode) else {
      throw SubscriptionError.invalidResponse
    }
    guard let text = String(data: data, encoding: .utf8) else {
      throw SubscriptionError.unsupportedEncoding
    }
    return SubscriptionFetchResult(
      nodes: try ShareLinkParser.parseMany(text),
      etag: httpResponse.value(forHTTPHeaderField: "ETag"),
      lastModified: httpResponse.value(forHTTPHeaderField: "Last-Modified")
    )
  }
}
