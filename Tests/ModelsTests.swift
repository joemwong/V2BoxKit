import XCTest

#if SWIFT_PACKAGE
  @testable import V2BoxCore
#else
  @testable import V2BoxKit
#endif

final class ModelsTests: XCTestCase {
  func testSubscriptionRefreshDueDate() {
    let now = Date(timeIntervalSince1970: 10_000)
    let recent = ProxySubscription(
      name: "test",
      url: URL(string: "https://example.com/sub")!,
      refreshInterval: .sixHours,
      lastUpdatedAt: now.addingTimeInterval(-60)
    )
    var old = recent
    old.lastUpdatedAt = now.addingTimeInterval(-7 * 3600)

    XCTAssertFalse(recent.isDue(at: now))
    XCTAssertTrue(old.isDue(at: now))
  }

  func testLegacyNodeDecodingUsesSafeDefaults() throws {
    let id = UUID()
    let json = """
      {"id":"\(id.uuidString)","name":"legacy","kind":"vless","host":"example.com","port":443,"rawURI":"vless://id@example.com:443"}
      """
    let node = try JSONDecoder().decode(ProxyNode.self, from: Data(json.utf8))

    XCTAssertEqual(node.groupName, "手动导入")
    XCTAssertFalse(node.isFavorite)
    XCTAssertNil(node.source.subscriptionID)
  }

  func testConfigurationArchiveValidation() throws {
    let node = ProxyNode(
      name: "backup",
      kind: .vless,
      host: "example.com",
      port: 443,
      rawURI: "vless://id@example.com:443"
    )
    let archive = ConfigurationArchive(
      nodes: [node],
      subscriptions: [],
      routing: RoutingSettings(),
      settings: ApplicationSettings(),
      selectedNodeID: node.id
    )

    XCTAssertNoThrow(try archive.validate())
    XCTAssertEqual(archive.formatVersion, ConfigurationArchive.currentFormatVersion)
  }

  func testOnDemandAndLocalSharingDefaultsDecodeFromLegacySettings() throws {
    let application = try JSONDecoder().decode(ApplicationSettings.self, from: Data("{}".utf8))
    let routing = try JSONDecoder().decode(RoutingSettings.self, from: Data("{}".utf8))

    XCTAssertFalse(application.onDemand.isEnabled)
    XCTAssertFalse(application.iCloudSyncEnabled)
    XCTAssertFalse(routing.localSharing.isEnabled)
    XCTAssertTrue(routing.localSharing.isValid)
  }
}
