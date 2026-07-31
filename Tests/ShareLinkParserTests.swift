import XCTest

#if SWIFT_PACKAGE
  @testable import V2BoxCore
#else
  @testable import V2BoxKit
#endif

final class ShareLinkParserTests: XCTestCase {
  func testParsesVLESSLink() throws {
    let link =
      "vless://11111111-1111-1111-1111-111111111111@example.com:443?security=tls&type=ws#Hong%20Kong"
    let node = try ShareLinkParser.parse(link)

    XCTAssertEqual(node.kind, .vless)
    XCTAssertEqual(node.name, "Hong Kong")
    XCTAssertEqual(node.host, "example.com")
    XCTAssertEqual(node.port, 443)
  }

  func testParsesLegacyVMessLink() throws {
    let json =
      #"{"v":"2","ps":"Tokyo","add":"jp.example.com","port":"443","id":"11111111-1111-1111-1111-111111111111","net":"ws","tls":"tls"}"#
    let link = "vmess://" + Data(json.utf8).base64EncodedString()
    let node = try ShareLinkParser.parse(link)

    XCTAssertEqual(node.kind, .vmess)
    XCTAssertEqual(node.name, "Tokyo")
    XCTAssertEqual(node.endpoint, "jp.example.com:443")
  }

  func testParsesBase64SubscriptionAndSkipsInvalidLines() throws {
    let plain = """
      invalid
      trojan://secret@one.example.com:443#One
      hysteria2://secret@two.example.com:8443?sni=two.example.com#Two
      """
    let encoded = Data(plain.utf8).base64EncodedString()
    let nodes = try ShareLinkParser.parseMany(encoded)

    XCTAssertEqual(nodes.count, 2)
    XCTAssertEqual(Set(nodes.map(\.kind)), Set([.trojan, .hysteria2]))
  }

  func testRejectsUnknownScheme() {
    XCTAssertThrowsError(try ShareLinkParser.parse("unknown://example.com:1"))
  }
}
