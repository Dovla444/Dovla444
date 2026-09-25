// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SyncKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SyncKit", targets: ["SyncKit"]),
    ],
    dependencies: [
        // libgit2 1.9.2 compiled from source by SwiftPM (HTTPS via the system TLS stack, no OpenSSL).
        // Why this package: see docs/PHASE0.md.
        .package(url: "https://github.com/ibrahimcetin/libgit2.git", exact: "1.9.2"),
    ],
    targets: [
        .target(
            name: "SyncKit",
            dependencies: [.product(name: "libgit2", package: "libgit2")]
        ),
        .testTarget(
            name: "SyncKitTests",
            dependencies: ["SyncKit"]
        ),
    ]
)
