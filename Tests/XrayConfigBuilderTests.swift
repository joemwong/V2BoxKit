import XCTest

#if SWIFT_PACKAGE
  @testable import V2BoxCore
#else
  @testable import V2BoxKit
#endif

final class XrayConfigBuilderTests: XCTestCase {
  func testBuildsTunConfigurationWithRuleRouting() throws {
    let base: [String: Any] = [
      "outbounds": [
        [
          "protocol": "trojan",
          "settings": ["servers": [["address": "example.com", "port": 443, "password": "secret"]]],
        ]
      ]
    ]
    let routing = RoutingSettings(
      mode: .rule,
      bypassPrivateNetworks: true,
      directDomains: ["apple.com", "APPLE.com", ""]
    )

    let json = try XrayConfigBuilder.build(
      baseConfiguration: base,
      tunnelFileDescriptor: 42,
      routing: routing
    )
    let data = try XCTUnwrap(json.data(using: .utf8))
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertEqual((object["env"] as? [String: String])?["xray.tun.fd"], "42")
    let inbounds = try XCTUnwrap(object["inbounds"] as? [[String: Any]])
    XCTAssertEqual(inbounds.first?["protocol"] as? String, "tun")

    let outbounds = try XCTUnwrap(object["outbounds"] as? [[String: Any]])
    XCTAssertEqual(outbounds.map { $0["tag"] as? String }, ["proxy", "direct", "block"])

    let routingObject = try XCTUnwrap(object["routing"] as? [String: Any])
    let rules = try XCTUnwrap(routingObject["rules"] as? [[String: Any]])
    XCTAssertEqual(rules.count, 2)
    XCTAssertEqual(rules[1]["domain"] as? [String], ["domain:apple.com"])
  }

  func testDirectModeRoutesEveryConnectionDirectly() throws {
    let base: [String: Any] = ["outbounds": [["protocol": "freedom"]]]
    let json = try XrayConfigBuilder.build(
      baseConfiguration: base,
      tunnelFileDescriptor: 7,
      routing: RoutingSettings(mode: .direct)
    )
    let data = try XCTUnwrap(json.data(using: .utf8))
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let routingObject = try XCTUnwrap(object["routing"] as? [String: Any])
    let rules = try XCTUnwrap(routingObject["rules"] as? [[String: Any]])

    XCTAssertEqual(rules.first?["outboundTag"] as? String, "direct")
  }

  func testCustomRulesKeepPriorityAndMTU() throws {
    let base: [String: Any] = ["outbounds": [["protocol": "freedom"]]]
    let routing = RoutingSettings(
      customRules: [
        RoutingRule(name: "Block ads", kind: .domain, values: ["ads.example"], action: .block),
        RoutingRule(name: "Proxy range", kind: .ip, values: ["203.0.113.0/24"], action: .proxy),
      ],
      mtu: 1380
    )
    let json = try XrayConfigBuilder.build(
      baseConfiguration: base,
      tunnelFileDescriptor: 9,
      routing: routing
    )
    let data = try XCTUnwrap(json.data(using: .utf8))
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let inbounds = try XCTUnwrap(object["inbounds"] as? [[String: Any]])
    let settings = try XCTUnwrap(inbounds[0]["settings"] as? [String: Any])
    XCTAssertEqual(settings["mtu"] as? Int, 1380)

    let routingObject = try XCTUnwrap(object["routing"] as? [String: Any])
    let rules = try XCTUnwrap(routingObject["rules"] as? [[String: Any]])
    XCTAssertEqual(rules[0]["domain"] as? [String], ["domain:ads.example"])
    XCTAssertEqual(rules[0]["outboundTag"] as? String, "block")
    XCTAssertEqual(rules[1]["ip"] as? [String], ["203.0.113.0/24"])
  }

  func testAuthenticatedLocalSharingInbounds() throws {
    let base: [String: Any] = ["outbounds": [["protocol": "freedom"]]]
    let sharing = LocalSharingSettings(
      isEnabled: true,
      allowLocalNetwork: true,
      socksPort: 10808,
      httpPort: 10809,
      username: "alice",
      password: "strong-password"
    )
    let json = try XrayConfigBuilder.build(
      baseConfiguration: base,
      tunnelFileDescriptor: 5,
      routing: RoutingSettings(localSharing: sharing)
    )
    let data = try XCTUnwrap(json.data(using: .utf8))
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let inbounds = try XCTUnwrap(object["inbounds"] as? [[String: Any]])

    XCTAssertEqual(inbounds.count, 3)
    XCTAssertEqual(inbounds[1]["protocol"] as? String, "socks")
    XCTAssertEqual(inbounds[1]["listen"] as? String, "0.0.0.0")
    XCTAssertEqual(inbounds[2]["protocol"] as? String, "http")
    let settings = try XCTUnwrap(inbounds[1]["settings"] as? [String: Any])
    let accounts = try XCTUnwrap(settings["accounts"] as? [[String: String]])
    XCTAssertEqual(accounts.first?["user"], "alice")
  }
}
