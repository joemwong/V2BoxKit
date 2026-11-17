import Darwin
import Foundation
import LibXray

enum LibXrayInvoker {
  enum InvocationError: LocalizedError {
    case requestEncodingFailed
    case emptyResponse
    case malformedResponse
    case coreError(String)

    var errorDescription: String? {
      switch self {
      case .requestEncodingFailed: "无法编码 libXray 请求"
      case .emptyResponse: "libXray 没有返回结果"
      case .malformedResponse: "libXray 返回格式异常"
      case .coreError(let message): "Xray：\(message)"
      }
    }
  }

  static func configuration(forShareLink link: String) throws -> [String: Any] {
    let result = try invoke(
      method: "convertShareLinksToXrayJson", payload: ["text": try ShareLinkParser.runtimeLink(link)])
    guard var config = result as? [String: Any],
      var outbounds = config["outbounds"] as? [[String: Any]], !outbounds.isEmpty
    else { throw InvocationError.malformedResponse }

    for index in outbounds.indices {
      // libXray v26.7.11 puts display names here; the runtime expects a source IP.
      outbounds[index].removeValue(forKey: "sendThrough")
      guard var stream = outbounds[index]["streamSettings"] as? [String: Any],
        var reality = stream["realitySettings"] as? [String: Any]
      else { continue }
      // Presence of a server-only key, even JSON null, selects server mode in this core.
      for key in ["target", "dest"] where reality[key] is NSNull {
        reality.removeValue(forKey: key)
      }
      stream["realitySettings"] = reality
      outbounds[index]["streamSettings"] = stream
    }
    config["outbounds"] = outbounds
    return config
  }

  static func invoke(method: String, payload: [String: Any]? = nil) throws -> Any {
    var request: [String: Any] = ["apiVersion": 1, "method": method]
    if let payload { request["payload"] = payload }
    guard JSONSerialization.isValidJSONObject(request),
      let requestData = try? JSONSerialization.data(withJSONObject: request),
      let requestString = String(data: requestData, encoding: .utf8),
      let requestPointer = strdup(requestString)
    else {
      throw InvocationError.requestEncodingFailed
    }
    defer { free(requestPointer) }
    guard let responsePointer = CGoInvoke(requestPointer) else {
      throw InvocationError.emptyResponse
    }
    defer { CGoFree(responsePointer) }

    let responseString = String(cString: responsePointer)
    guard let responseData = responseString.data(using: .utf8),
      let response = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
      let success = response["success"] as? Bool
    else {
      throw InvocationError.malformedResponse
    }
    guard success else {
      throw InvocationError.coreError(response["error"] as? String ?? "未知错误")
    }
    return response["data"] ?? [:]
  }
}
