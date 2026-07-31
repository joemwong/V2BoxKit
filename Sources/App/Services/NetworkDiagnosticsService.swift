import Darwin
import Foundation

struct DiagnosticCheck: Identifiable, Sendable {
  let id = UUID()
  let name: String
  let result: String
  let succeeded: Bool
}

struct NetworkDiagnosticsService {
  func run(publicIPURL: URL, tunnelManager: TunnelManager) async -> [DiagnosticCheck] {
    var checks: [DiagnosticCheck] = []
    do {
      var request = URLRequest(url: publicIPURL)
      request.timeoutInterval = 8
      let (data, response) = try await URLSession.shared.data(for: request)
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      guard (200..<300).contains(status) else { throw URLError(.badServerResponse) }
      let value =
        String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "响应为空"
      checks.append(
        DiagnosticCheck(name: "公网出口", result: String(value.prefix(120)), succeeded: true))
    } catch {
      checks.append(
        DiagnosticCheck(name: "公网出口", result: error.localizedDescription, succeeded: false))
    }

    let dns = await Task.detached(priority: .utility) {
      var result: UnsafeMutablePointer<addrinfo>?
      let code = getaddrinfo("www.cloudflare.com", "443", nil, &result)
      if let result { freeaddrinfo(result) }
      return code
    }.value
    checks.append(
      DiagnosticCheck(
        name: "DNS 解析",
        result: dns == 0 ? "www.cloudflare.com 解析成功" : String(cString: gai_strerror(dns)),
        succeeded: dns == 0
      ))

    do {
      let info = try await tunnelManager.runtimeInfo()
      checks.append(DiagnosticCheck(name: "隧道核心", result: info, succeeded: true))
    } catch {
      checks.append(
        DiagnosticCheck(name: "隧道核心", result: error.localizedDescription, succeeded: false))
    }
    return checks
  }
}
