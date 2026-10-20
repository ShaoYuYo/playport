// SPDX-License-Identifier: GPL-3.0-or-later
/// Network route observations describe the UI; they are not proof a local
/// developer connection will fail. Recovery follows a real request, once.
public enum JitLaunchPolicy {
    public static func recoverVPN(requestFailed: Bool, recoveryAttempted: Bool, tunnelUp: Bool) -> Bool {
        requestFailed && !recoveryAttempted && !tunnelUp
    }
}
