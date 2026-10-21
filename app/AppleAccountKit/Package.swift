// swift-tools-version: 6.0
// SPDX-License-Identifier: GPL-3.0-or-later
import PackageDescription
let package = Package(name: "AppleAccountKit", platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "AppleAccountKit", targets: ["AppleAccountKit"])],
    dependencies: [
        .package(url: "https://github.com/attaswift/BigInt", revision: "e07e00fa1fd435143a2dcf8b7eec9a7710b2fdfe"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift", revision: "e45a26384239e028ec87fbcc788f513b67e10d8f")
    ], targets: [
        .target(name: "AppleAccountKit", dependencies: [.product(name: "BigInt", package: "BigInt"), .product(name: "CryptoSwift", package: "CryptoSwift")],
             swiftSettings: [.unsafeFlags(["-O"], .when(configuration: .debug))]),
        .testTarget(name: "AppleAccountKitTests", dependencies: ["AppleAccountKit"])
    ], swiftLanguageModes: [.v5])
