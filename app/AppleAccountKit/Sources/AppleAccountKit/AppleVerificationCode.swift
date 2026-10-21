// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// One challenge per sign-in. Accepts entry while Apple's delivery request is
/// still returning; cancellation, late submissions and duplicate sends are safe.
@MainActor
public final class AppleVerificationCode {
    private var pending: CheckedContinuation<String, Error>?
    private var buffered: String?
    private var finished = false
    public init() {}
    public static func normalized(_ input: String) -> String? {
        var digits = ""
        for scalar in input.unicodeScalars {
            switch scalar.value {
            case 48...57: digits.unicodeScalars.append(scalar)
            case 0xFF10...0xFF19: digits.unicodeScalars.append(UnicodeScalar(scalar.value - 0xFF10 + 48)!)
            default:
                guard CharacterSet.whitespacesAndNewlines.contains(scalar) || scalar == "-" else { return nil }
            }
        }
        return digits.utf8.count == 6 ? digits : nil
    }
    @discardableResult
    public func submit(_ input: String) -> Bool {
        guard !finished, buffered == nil, let code = Self.normalized(input) else { return false }
        if let pending {
            self.pending = nil; finished = true; pending.resume(returning: code)
        } else { buffered = code }
        return true
    }
    public func value() async throws -> String {
        try Task.checkCancellation()
        guard !finished, pending == nil else { throw AppleProvisioningError.cancelled }
        if let buffered { self.buffered = nil; finished = true; return buffered }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { pending = $0 }
        } onCancel: { Task { @MainActor in self.cancel() } }
    }
    public func cancel() {
        finished = true; buffered = nil
        let waiter = pending; pending = nil
        waiter?.resume(throwing: AppleProvisioningError.cancelled)
    }
}
