// swift-tools-version:6.0
import PackageDescription

// This package is deliberately .xcodeproj-free — same rationale as the sibling
// `mudbase-showcase-ecommerce/swift` and `mudbase-showcase-social/swift` ports this app's
// architecture is ported from (see README.md "Why SPM, not an .xcodeproj"). Xcode 14+ opens
// Package.swift directly and runs an `executableTarget` that defines a SwiftUI `App`/`@main` as a
// real iOS app on a Simulator or device. `swift build` from the CLI also succeeds on macOS — the
// platforms list below just sets minimum deployment targets; no UIKit-only symbols are used
// anywhere in this target.
let package = Package(
    name: "MudbaseShowcaseDocsSearch",
    platforms: [
        .iOS(.v16),
        // v14, not v13 — matches the sibling ecommerce/social Swift ports' platforms list: a few
        // `.textContentType` cases only landed on macOS in 14.0 even though their iOS
        // availability is much older. This only affects the secondary macOS target used for
        // `swift build` CLI verification; the real iOS 16 deployment target is unaffected.
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "MudbaseShowcaseDocsSearch",
            targets: ["MudbaseShowcaseDocsSearch"]
        ),
    ],
    dependencies: [
        // Sibling-clone dependency — see README.md "Setup" for the required directory layout and
        // the SwiftPM package-identity-collision rationale (this package's own directory is named
        // `swift`, same as the SDK repo's Swift subdirectory — pointing straight at
        // `mudbase-sdk/swift` would conflate the two package identities). `mudbase-sdk-swift` is a
        // relative symlink committed at this monorepo's root
        // (`mudbase-showcase-docs-search/mudbase-sdk-swift -> ../mudbase-sdk/swift`), the exact
        // same workaround the ecommerce Swift port established first.
        .package(name: "MudbaseSDK", path: "../mudbase-sdk-swift"),
    ],
    targets: [
        .executableTarget(
            name: "MudbaseShowcaseDocsSearch",
            dependencies: [
                .product(name: "MudbaseSDK", package: "MudbaseSDK"),
            ],
            path: "Sources/MudbaseShowcaseDocsSearch"
        ),
        // Standalone, headless verification against the real, live `cloud.mudbase.dev` project —
        // `@testable import` is the only way for a separate SPM target to reach this app's own
        // internal `Services`/`Networking`/`Models` types. Disabled by default — see
        // `ManualLiveFlowTests.swift` — so a plain `swift test` never makes network calls or
        // writes real documents on its own.
        .testTarget(
            name: "ManualLiveFlowTests",
            dependencies: ["MudbaseShowcaseDocsSearch"],
            path: "Tests/ManualLiveFlowTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
