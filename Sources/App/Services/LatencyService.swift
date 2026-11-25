import Foundation

/// libXray calls are synchronous and a ping can block for the whole timeout. Running them on a
/// global dispatch queue (instead of an actor on the Swift cooperative pool) avoids starving the
/// pool and lets several probes run in parallel.
struct LatencyService: Sendable {
  private static let timeoutSeconds = 6
  static let failureLatency = 10_000

  /// - Parameter port: a pre-reserved loopback port. Parallel callers should
  ///   reserve distinct ports with `freePorts(count:)`; asking one at a time
  ///   can hand two probes the same port.
  func measure(node: ProxyNode, port: Int? = nil) async -> Int {
    await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        continuation.resume(returning: Self.measureBlocking(node: node, reservedPort: port))
      }
    }
  }

  func freePorts(count: Int) async -> [Int] {
    await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        continuation.resume(returning: (try? Self.freePortsBlocking(count: count)) ?? [])
      }
    }
  }

  private static func freePortsBlocking(count: Int) throws -> [Int] {
    guard
      let portData = try LibXrayInvoker.invoke(
        method: "getFreePorts",
        payload: ["count": max(1, count)]
      ) as? [String: Any],
      let ports = portData["ports"] as? [Int], !ports.isEmpty
    else {
      throw LibXrayInvoker.InvocationError.malformedResponse
    }
    return ports
  }

  private static func measureBlocking(node: ProxyNode, reservedPort: Int?) -> Int {
    do {
      let port = try reservedPort ?? freePortsBlocking(count: 1)[0]

      var configuration = try LibXrayInvoker.configuration(forShareLink: node.rawURI)
      configuration["log"] = ["loglevel": "warning"]
      configuration["inbounds"] = [
        [
          "tag": "latency-in",
          "listen": "127.0.0.1",
          "port": port,
          "protocol": "socks",
          "settings": ["udp": false],
        ]
      ]

      let data = try JSONSerialization.data(withJSONObject: configuration)
      let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("v2boxkit-ping-\(UUID().uuidString).json")
      try data.write(to: fileURL, options: .atomic)
      defer { try? FileManager.default.removeItem(at: fileURL) }

      guard
        let result = try LibXrayInvoker.invoke(
          method: "ping",
          payload: [
            "configPath": fileURL.path,
            "timeout": timeoutSeconds,
            "url": AppConstants.latencyTestURL,
            "proxy": "socks5://127.0.0.1:\(port)",
          ]) as? [String: Any], let delay = result["delay"] as? Int
      else {
        throw LibXrayInvoker.InvocationError.malformedResponse
      }
      return delay
    } catch {
      DiagnosticLogStore.shared.append(
        .warning,
        category: "latency",
        message: "节点测速失败：\(node.name)"
      )
      return failureLatency
    }
  }
}
