// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import XCTest
@testable import SteamClientKit

private actor CloudReadProbe {
    var failures: [SteamError]
    var attempts = 0
    var waits: [UInt64] = []
    init(_ failures: [SteamError]) { self.failures = failures }
    func read() throws -> Int {
        attempts += 1
        if !failures.isEmpty { throw failures.removeFirst() }
        return 7
    }
    func pause(_ delay: UInt64) { waits.append(delay) }
    func failAgain(_ failures: [SteamError]) { self.failures = failures }
    func snapshot() -> (Int, [UInt64]) { (attempts, waits) }
}

final class CloudReadRetryTests: XCTestCase {
    let busy = SteamError.eresult(.busy, context: "Cloud.ClientFileDownload#1")

    func testBusyReadBacksOffThenReturnsTheSuccessfulBytes() async throws {
        let probe = CloudReadProbe([busy, busy])
        let retry = Cloud.ReadRetry(pause: { await probe.pause($0) })
        let value = try await retry.run { try await probe.read() }
        XCTAssertEqual(value, 7)
        let (attempts, waits) = await probe.snapshot()
        XCTAssertEqual(attempts, 3); XCTAssertEqual(waits, [500_000_000, 1_000_000_000])
    }

    func testRetryBudgetIsSharedAcrossFilesAndExhaustionKeepsBusyError() async throws {
        let probe = CloudReadProbe(Array(repeating: busy, count: 4))
        let retry = Cloud.ReadRetry(pause: { await probe.pause($0) })
        do { _ = try await retry.run { try await probe.read() }; XCTFail("must exhaust") }
        catch { XCTAssertEqual(error as? SteamError, busy) }
        await probe.failAgain([busy])
        do { _ = try await retry.run { try await probe.read() }; XCTFail("budget must not reset for another file") }
        catch { XCTAssertEqual(error as? SteamError, busy) }
        let (attempts, waits) = await probe.snapshot()
        XCTAssertEqual(attempts, 5); XCTAssertEqual(waits, [500_000_000, 1_000_000_000, 2_000_000_000])
    }

    func testPermissionTimeoutIntegrityAndDuplicateFailuresAreNotReplayed() async throws {
        for failure in [SteamError.eresult(.accessDenied, context: "read"), .eresult(.duplicateRequest, context: "read"),
                        .timeout("read"), .verificationFailed("bad bytes")] {
            let probe = CloudReadProbe([failure])
            let retry = Cloud.ReadRetry(pause: { await probe.pause($0) })
            do { _ = try await retry.run { try await probe.read() }; XCTFail("must not retry this failure") }
            catch { XCTAssertEqual(error as? SteamError, failure) }
            let (attempts, waits) = await probe.snapshot()
            XCTAssertEqual(attempts, 1); XCTAssertTrue(waits.isEmpty)
        }
    }

    func testCancellationDuringBackoffNeverMakesAnotherRequest() async throws {
        let probe = CloudReadProbe([busy])
        let retry = Cloud.ReadRetry(pause: { _ in throw CancellationError() })
        do { _ = try await retry.run { try await probe.read() }; XCTFail("must cancel") }
        catch { XCTAssertTrue(error is CancellationError) }
        let (attempts, _) = await probe.snapshot()
        XCTAssertEqual(attempts, 1)
    }
}
