// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
import Foundation
@testable import AppleAccountKit
final class AppleRequestPolicyTests: XCTestCase {
    func testAuthenticationMetadataDoesNotLeakIntoPortalOrProvisioning() {
        let headers = AppleRequestPolicy.authenticationHeaders(URL(string: "https://gsa.apple.com/grandslam/GsService2")!)
        XCTAssertEqual(headers["User-Agent"], "akd/1.0 CFNetwork/808.1.4")
        XCTAssertEqual(headers["X-Apple-App-Info"], "com.apple.gs.xcode.auth")
        XCTAssertEqual(headers["Accept"], "text/x-xml-plist")
        for raw in ["https://developerservices2.apple.com/services/", "https://ani.sidestore.io", "https://gsa.apple.com/grandslam/GsService2/lookup", "https://gsa.apple.com/auth/verify/trusteddevice", "http://gsa.apple.com/grandslam/GsService2"] {
            XCTAssertEqual(AppleRequestPolicy.authenticationHeaders(URL(string: raw)!), [:])
        }
    }
    func testGrandSlamUsesCompleteCompatibleDescriptor() {
        let raw = "<Mac14,1> <macOS;26.0> <com.apple.AuthKit/1 (com.apple.dt.Xcode/3594.4.19)>"
        let actual = AppleRequestPolicy.clientInfo(raw, url: URL(string: "https://gsa.apple.com/grandslam/GsService2")!)
        XCTAssertEqual(actual, "<PC> <Windows;6.2(0,0);9200> <com.apple.AuthKit/1 (com.apple.akd/1.0)>")
        XCTAssertFalse(actual.contains("com.apple.dt.Xcode"))
    }
    func testProvisioningTwoFactorAndOtherOriginsKeepTheirIdentity() {
        let raw = "<Mac14,1><com.apple.dt.Xcode/3594.4.19>"
        for host in ["developerservices2.apple.com", "ani.sidestore.io"] {
            XCTAssertEqual(AppleRequestPolicy.clientInfo(raw, url: URL(string: "https://" + host)!), raw)
        }
        for path in ["/", "/grandslam/GsService2/lookup", "/auth/verify/trusteddevice"] {
            XCTAssertEqual(AppleRequestPolicy.clientInfo(raw, url: URL(string: "https://gsa.apple.com" + path)!), raw)
        }
        let current = "<PC> <Windows;6.2(0,0);9200> <com.apple.AuthKit/1 (com.apple.akd/1.0)>"
        XCTAssertEqual(AppleRequestPolicy.clientInfo(current, url: URL(string: "https://gsa.apple.com/grandslam/GsService2/validate")!), current)
        XCTAssertFalse(AppleRequestPolicy.grandSlam(URL(string: "https://gsa.apple.com/grandslam/GsService2/evil")))
    }
    func testStructuredRejectionAndUntrustedBodies() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["Response": ["Status": ["ec": -80045]]], format: .xml, options: 0)
        XCTAssertEqual(AppleRequestPolicy.rejection(in: data), -80045)
        XCTAssertNil(AppleRequestPolicy.rejection(in: Data("<html>503</html>".utf8)))
        XCTAssertNil(AppleRequestPolicy.rejection(in: try PropertyListSerialization.data(fromPropertyList: ["Response": ["Status": ["ec": 0]]], format: .xml, options: 0)))
        XCTAssertTrue(AppleProvisioningError.rejected(-80045).localizedDescription.contains("不能用來判定密碼錯誤"))
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
