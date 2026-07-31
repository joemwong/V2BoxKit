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
