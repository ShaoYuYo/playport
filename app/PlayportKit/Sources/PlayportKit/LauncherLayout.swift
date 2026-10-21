// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Widths are the safe content area, not raw display pixels.
public struct LauncherLayout: Equatable, Sendable {
    public let width: Double
    public init(width: Double) { self.width = width.isFinite ? max(0, width) : 0 }
    public var stackedSettings: Bool { width < 620 }
    public var settingsSidebar: Double { width < 800 ? 170 : 210 }
    public var panelWidth: Double { min(410, max(0, width - 16)) }
    public var libraryColumns: Int { max(1, min(7, Int((max(0, width - 16) + 14) / 150))) }
    public var stackedGame: Bool { width < 760 }
    public var gameTopInset: Double { width < 850 ? 18 : 36 }
}
