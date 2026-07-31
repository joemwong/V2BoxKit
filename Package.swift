// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "V2BoxCore",
  platforms: [.iOS(.v17)],
  products: [
    .library(name: "V2BoxCore", targets: ["V2BoxCore"])
  ],
  targets: [
    .target(
      name: "V2BoxCore",
      path: "Sources",
      exclude: [
        "App/AppDelegate.swift",
        "App/V2BoxKitApp.swift",
        "App/Views",
        "App/Services/BackupDocument.swift",
        "App/Services/CloudSyncService.swift",
        "App/Services/DeepLinkImporter.swift",
        "App/Services/LatencyService.swift",
        "App/Services/LocalNetworkAddressResolver.swift",
        "App/Services/NetworkDiagnosticsService.swift",
        "App/Services/NodeStore.swift",
        "App/Services/SecureArchiveService.swift",
        "App/Services/SubscriptionService.swift",
        "App/Services/TunnelManager.swift",
        "PacketTunnel",
        "Shared/AppConstants.swift",
        "Shared/Diagnostics",
        "Shared/LibXrayInvoker.swift",
      ],
      sources: [
        "Shared/Models/ConfigurationArchive.swift",
        "Shared/Models/ProxyNode.swift",
        "Shared/Models/RoutingSettings.swift",
        "Shared/Models/ApplicationSettings.swift",
        "Shared/Models/Subscription.swift",
        "Shared/XrayConfigBuilder.swift",
        "App/Services/ShareLinkParser.swift",
      ]
    ),
    .testTarget(
      name: "V2BoxCoreTests",
      dependencies: ["V2BoxCore"],
      path: "Tests",
      sources: [
        "ModelsTests.swift",
        "ShareLinkParserTests.swift",
        "XrayConfigBuilderTests.swift",
      ]
    ),
  ]
)
