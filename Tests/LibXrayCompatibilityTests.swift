import Foundation
import Testing
@testable import V2BoxKit

@Suite(.serialized)
struct LibXrayCompatibilityTests {
  // Synthetic credentials and reserved addresses. testXray validates without starting a VPN.
  private func checkedOutbound(_ link: String) throws -> [String: Any] {
    let node = try ShareLinkParser.parse(link)
    #expect(node.rawURI == link)
    let config = try LibXrayInvoker.configuration(forShareLink: node.rawURI)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try JSONSerialization.data(withJSONObject: config).write(to: url)
    _ = try LibXrayInvoker.invoke(method: "testXray", payload: ["configPath": url.path])
    let outbound = try #require((config["outbounds"] as? [[String: Any]])?.first)
    #expect(outbound["sendThrough"] == nil)
    return outbound
  }

  @Test func shadowsocksEncodingsPreserveCredentialsAndIPv6() throws {
    let credentials = "aes-128-gcm:demo@p:a/ss"
    let endpoint = "[2001:db8::1]:443"
    let legacy = Data("\(credentials)@\(endpoint)".utf8).base64EncodedString()
    let userInfo = Data(credentials.utf8).base64EncodedString()
    for address in [legacy, "\(userInfo)@\(endpoint)", "aes-128-gcm:demo%40p%3Aa%2Fss@\(endpoint)"] {
      let outbound = try checkedOutbound("ss://\(address)#Demo")
      let settings = try #require(outbound["settings"] as? [String: Any])
      #expect(settings["method"] as? String == "aes-128-gcm")
      #expect(settings["password"] as? String == "demo@p:a/ss")
      #expect(settings["address"] as? String == "[2001:db8::1]")
      #expect(settings["port"] as? Int == 443)
    }
  }

  @Test func legacyVMessWithDisplayFragment() throws {
    let json = #"{"v":"2","ps":"Tokyo","add":"example.com","port":"443","id":"11111111-1111-4111-8111-111111111111","aid":"0","net":"tcp","type":"none","tls":""}"#
    let link = "vmess://\(Data(json.utf8).base64EncodedString())#Tokyo%20Test"
    let outbound = try checkedOutbound(link)
    #expect(outbound["protocol"] as? String == "vmess")
  }

  @Test func rejectsLegacyShadowsocksWithoutPort() {
    let invalid = Data("aes-128-gcm:example@host.example".utf8).base64EncodedString()
    #expect(throws: ShareLinkParser.ParserError.self) { try ShareLinkParser.parse("ss://" + invalid) }
  }

  @Test func realityRetainsClientParameters() throws {
    let key = "AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA"
    let link = "vless://11111111-1111-4111-8111-111111111111@example.com:443"
      + "?security=reality&amp;type=tcp&amp;fp=chrome&amp;sni=example.com&amp;pbk=\(key)&amp;sid=1234#Demo"
    let outbound = try checkedOutbound(link)
    let stream = try #require(outbound["streamSettings"] as? [String: Any])
    let reality = try #require(stream["realitySettings"] as? [String: Any])
    #expect(reality["target"] == nil && reality["dest"] == nil)
    #expect(reality["serverName"] as? String == "example.com")
    #expect(reality["shortId"] as? String == "1234")
    #expect(reality["publicKey"] as? String == key)
  }
}
