import Foundation

actor LatencyService {
  private let timeoutSeconds = 6

  func measure(node: ProxyNode) async -> Int {
    do {
      guard
        let portData = try LibXrayInvoker.invoke(
          method: "getFreePorts",
          payload: ["count": 1]
        ) as? [String: Any],
        let port = (portData["ports"] as? [Int])?.first
      else {
        throw LibXrayInvoker.InvocationError.malformedResponse
      }

      let converted = try LibXrayInvoker.invoke(
        method: "convertShareLinksToXrayJson",
        payload: ["text": node.rawURI]
      )
      guard var configuration = converted as? [String: Any] else {
        throw LibXrayInvoker.InvocationError.malformedResponse
      }
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
      return 10_000
    }
  }
}
