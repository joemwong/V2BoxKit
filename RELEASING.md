# Release process

V2BoxKit uses independent semantic-version tags for each client.

| Client | Tag pattern | Release asset |
|---|---|---|
| iOS / iPadOS | `ios-vX.Y.Z` | Source ZIP; signed IPA requires publisher credentials |
| Android | `android-vX.Y.Z` | APK |
| Windows | `windows-vX.Y.Z` | Portable x64 ZIP |

Examples:

```bash
git tag ios-v1.0.0
git tag android-v1.0.0
git tag windows-v1.0.0
git push origin ios-v1.0.0 android-v1.0.0 windows-v1.0.0
```

Each tag triggers its matching GitHub Actions workflow and creates a GitHub prerelease.
Promote a release to stable only after the platform-specific validation documented in the README.

## Signing boundaries

- Android currently uses the debug signing configuration for MVP testing. Store releases need a private release keystore supplied through GitHub Actions secrets.
- iOS Network Extension builds need Apple signing certificates, App IDs, entitlements, and provisioning profiles. Those credentials are intentionally not stored in this repository.
- Windows builds are unsigned portable archives. Production distribution should add Authenticode signing.
