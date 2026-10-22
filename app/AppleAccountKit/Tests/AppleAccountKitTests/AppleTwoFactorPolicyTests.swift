// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import AppleAccountKit
final class AppleTwoFactorPolicyTests: XCTestCase {
    func testAllSupportedChallengeEnvelopes() {
        for mode in ["trustedDeviceSecondaryAuth", "trustedDevice"] {
            XCTAssertEqual(AppleTwoFactorPolicy.challenge(in: ["Status": ["au": mode]]), .trustedDevice(alreadySent: false))
        }
        for mode in ["secondaryAuth", "sms", "phone"] {
            XCTAssertEqual(AppleTwoFactorPolicy.challenge(in: ["au": mode]), .sms)
        }
    }
    func testAlreadyPushedCodeDoesNotRequestAnotherNotification() {
        XCTAssertEqual(AppleTwoFactorPolicy.challenge(in: ["Status": ["hsc": 409]]), .trustedDevice(alreadySent: true))
        XCTAssertEqual(AppleTwoFactorPolicy.challenge(in: ["au": "pushedCode"]), .trustedDevice(alreadySent: true))
    }
    func testUnknownAndUnchallengedResponsesRemainDistinct() {
        XCTAssertEqual(AppleTwoFactorPolicy.challenge(in: ["Status": ["ec": 0]]), .none)
        XCTAssertEqual(AppleTwoFactorPolicy.challenge(in: ["Status": ["au": "repair"]]), .unsupported)
        XCTAssertEqual(AppleTwoFactorPolicy.challenge(in: ["Status": ["hsc": 500]]), .none)
    }
    func testExplicitModeWinsOverHTTPMetadata() {
        XCTAssertEqual(AppleTwoFactorPolicy.challenge(in: ["au": "sms", "Status": ["hsc": 409]]), .sms)
        XCTAssertEqual(AppleTwoFactorPolicy.challenge(in: ["au": "sms", "Status": ["au": "trustedDevice"]]), .trustedDevice(alreadySent: false))
    }
    func testNestedValidationErrorsAreNotSuccess() throws {
        for payload: [String: Any] in [["ec": -21669], ["Status": ["ec": -21669]], ["Response": ["Status": ["ec": -21669]]]] {
            let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)
            XCTAssertEqual(AppleTwoFactorPolicy.rejection(in: data), -21669)
        }
    }
    func testEmptyAndUnstructuredResponsesDoNotInventAccountErrors() throws {
        XCTAssertNil(AppleTwoFactorPolicy.rejection(in: Data()))
        XCTAssertNil(AppleTwoFactorPolicy.rejection(in: Data("<html>unavailable</html>".utf8)))
        let data = try PropertyListSerialization.data(fromPropertyList: ["ec": 0], format: .xml, options: 0)
        XCTAssertNil(AppleTwoFactorPolicy.rejection(in: data))
    }
}
