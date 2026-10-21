// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import AppleAccountKit
final class AppleVerificationCodeTests: XCTestCase {
    @MainActor func testPasteNormalization() {
        XCTAssertEqual(AppleVerificationCode.normalized(" １２３-４５６\n"), "123456")
        XCTAssertEqual(AppleVerificationCode.normalized("012345"), "012345")
    }
    @MainActor func testMalformedCodeRejected() {
        for value in ["12345", "1234567", "12a456", "①23456", "１２３abc", ""] {
            XCTAssertNil(AppleVerificationCode.normalized(value))
        }
    }
    @MainActor func testEntryBeforeDeliveryReply() async throws {
        let gate = AppleVerificationCode()
        XCTAssertTrue(gate.submit("123 456"))
        XCTAssertFalse(gate.submit("654321"))
        let value = try await gate.value()
        XCTAssertEqual(value, "123456")
    }
    @MainActor func testEntryWhileWaiting() async throws {
        let gate = AppleVerificationCode()
        let task = Task { try await gate.value() }
        await Task.yield()
        XCTAssertFalse(gate.submit("abc"))
        XCTAssertTrue(gate.submit("012345"))
        let value = try await task.value
        XCTAssertEqual(value, "012345")
        XCTAssertFalse(gate.submit("654321"))
    }
    @MainActor func testClosingWhileWaiting() async {
        let gate = AppleVerificationCode()
        let task = Task { try await gate.value() }
        await Task.yield()
        gate.cancel(); gate.cancel()
        do { _ = try await task.value; XCTFail("cancelled prompt must not succeed") } catch {}
        XCTAssertFalse(gate.submit("123456"))
    }
    @MainActor func testCancelDiscardsEarlyCode() async {
        let gate = AppleVerificationCode()
        XCTAssertTrue(gate.submit("123456")); gate.cancel()
        do { _ = try await gate.value(); XCTFail("cancelled buffer must not escape") } catch {}
    }
    @MainActor func testTaskCancellationReleasesWaiter() async {
        let gate = AppleVerificationCode()
        let task = Task { try await gate.value() }
        await Task.yield(); task.cancel()
        do { _ = try await task.value; XCTFail("cancelled task must not succeed") } catch {}
    }
    @MainActor func testConsumedChallengeCannotBeReused() async throws {
        let gate = AppleVerificationCode(); gate.submit("123456")
        _ = try await gate.value()
        do { _ = try await gate.value(); XCTFail("must consume once") } catch {}
    }
    @MainActor func testNewSignInCannotUseOldChallenge() async throws {
        let old = AppleVerificationCode(); old.cancel()
        let current = AppleVerificationCode()
        XCTAssertFalse(old.submit("123456")); XCTAssertTrue(current.submit("654321"))
        let value = try await current.value(); XCTAssertEqual(value, "654321")
    }
}
