// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import PlayportKit

final class JitLaunchPreflightTests: XCTestCase {
    func testPairedLaunchAttemptsDespiteDownOrUnknownVPN() {
        for route: Bool? in [true, false, nil] {
            for onPhone in [true, false] {
                let facts = SetupFacts(pairing: true, pairsOnPhone: onPhone, tunnelUp: route)
                XCTAssertEqual(SetupChecklist.beforeLaunch(facts), .go)
            }
        }
    }

    func testMissingPairingStillUsesCorrectSetup() {
        for route: Bool? in [true, false, nil] {
            XCTAssertEqual(SetupChecklist.beforeLaunch(.init(pairing: false, pairsOnPhone: true, tunnelUp: route)),
                           .fixesItself(.pairing))
            guard case .needs(.pairing, _) = SetupChecklist.beforeLaunch(
                .init(pairing: false, pairsOnPhone: false, tunnelUp: route)) else { return XCTFail() }
        }
    }

    func testExternalMethodsAreNotRoutedThroughBuiltInSetup() {
        for method: JitMethod in [.stikDebug, .external] {
            XCTAssertEqual(SetupChecklist.beforeLaunch(.init(pairing: false, tunnelUp: false, jit: method)), .go)
        }
    }

    func testVPNRecoveryRequiresRealFailureAndIsBoundedToOneAttempt() {
        for failed in [true, false] {
            for attempted in [true, false] {
                for route in [true, false] {
                    let actual = JitLaunchPolicy.recoverVPN(requestFailed: failed,
                                                           recoveryAttempted: attempted, tunnelUp: route)
                    if failed && !attempted && !route { XCTAssertTrue(actual) }
                    else { XCTAssertFalse(actual) }
                }
            }
        }
    }
}
