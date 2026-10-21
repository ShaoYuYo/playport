// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
import Foundation
@testable import AppleAccountKit
final class AppleRequestPolicyTests: XCTestCase {
    func testAuthenticationDescriptorPreservesHardwareAndOS() {
        let raw = "<Mac14,1> <macOS;26.0> <com.apple.AuthKit/1 (com.apple.dt.Xcode/3594.4.19)>"
        let actual = AppleRequestPolicy.clientInfo(raw, url: URL(string: "https://gsa.apple.com/grandslam/GsService2")!)
        XCTAssertEqual(actual, "<Mac14,1> <macOS;26.0> <com.apple.AuthKit/1 (com.apple.akd/1.0)>")
        XCTAssertFalse(actual.contains("com.apple.dt.Xcode"))
    }
    func testOtherOriginsAndAlreadyCompatibleDescriptorsAreUntouched() {
        let raw = "<Mac14,1><com.apple.dt.Xcode/3594.4.19>"
        for host in ["developerservices2.apple.com", "ani.sidestore.io"] {
            XCTAssertEqual(AppleRequestPolicy.clientInfo(raw, url: URL(string: "https://" + host)!), raw)
        }
        let current = "<Mac14,1><com.apple.akd/1.0>"
        XCTAssertEqual(AppleRequestPolicy.clientInfo(current, url: URL(string: "https://gsa.apple.com")!), current)
    }
    func testSessionIsolationIsBoundToAuthenticationHTTPSOrigin() {
        XCTAssertTrue(AppleRequestPolicy.isolated(URL(string: "https://gsa.apple.com/grandslam/GsService2")))
        for raw in ["http://gsa.apple.com", "https://gsa.apple.com.example.invalid", "https://ani.sidestore.io"] {
            XCTAssertFalse(AppleRequestPolicy.isolated(URL(string: raw)))
        }
        XCTAssertFalse(AppleRequestPolicy.isolated(nil))
        XCTAssertTrue(AppleProvisioningError.http(503).localizedDescription.contains("503"))
    }
}
