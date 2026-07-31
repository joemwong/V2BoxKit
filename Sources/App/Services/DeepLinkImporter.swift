import Foundation

enum DeepLinkImporter {
  static func payload(from url: URL) -> String? {
    guard url.scheme?.lowercased() == AppConstants.importURLScheme else { return nil }
    if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let value = components.queryItems?.first(where: {
        ["url", "content", "text"].contains($0.name)
      })?.value,
      !value.isEmpty
    {
      return value
    }
    let prefix = "\(AppConstants.importURLScheme)://"
    let raw =
      url.absoluteString.hasPrefix(prefix)
      ? String(url.absoluteString.dropFirst(prefix.count))
      : url.absoluteString
    return raw.removingPercentEncoding ?? raw
  }
}
