import Foundation

final class XrayRuntime {
  func convertShareLink(_ link: String) throws -> Any {
    try LibXrayInvoker.invoke(method: "convertShareLinksToXrayJson", payload: ["text": link])
  }

  func run(configurationJSON: String) throws {
    _ = try LibXrayInvoker.invoke(
      method: "runXrayFromJson", payload: ["configJSON": configurationJSON])
  }

  func stop() {
    _ = try? LibXrayInvoker.invoke(method: "stopXray")
  }

  func version() -> String? {
    guard let data = try? LibXrayInvoker.invoke(method: "xrayVersion") as? [String: Any] else {
      return nil
    }
    return data["version"] as? String
  }

  func isRunning() -> Bool {
    guard let data = try? LibXrayInvoker.invoke(method: "getXrayState") as? [String: Any] else {
      return false
    }
    return data["running"] as? Bool ?? false
  }
}
