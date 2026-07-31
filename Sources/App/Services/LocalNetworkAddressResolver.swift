import Darwin
import Foundation

enum LocalNetworkAddressResolver {
  static var wiFiIPv4: String? {
    var interfaces: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&interfaces) == 0, let first = interfaces else { return nil }
    defer { freeifaddrs(interfaces) }

    for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
      let interface = pointer.pointee
      guard String(cString: interface.ifa_name) == "en0",
        let address = interface.ifa_addr,
        address.pointee.sa_family == UInt8(AF_INET)
      else { continue }

      var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      let result = getnameinfo(
        address,
        socklen_t(address.pointee.sa_len),
        &host,
        socklen_t(host.count),
        nil,
        0,
        NI_NUMERICHOST
      )
      if result == 0 { return String(cString: host) }
    }
    return nil
  }
}
