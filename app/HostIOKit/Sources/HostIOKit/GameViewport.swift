// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Keep the render view and controls in one coordinate space. Side rails are
/// outside the game's view and inside the window's camera/home-indicator insets.
public struct GameViewport: Sendable {
    public let safe: CGRect
    public let game: CGRect
    public let leftRail: CGRect
    public let rightRail: CGRect

    public init(width: Double, height: Double, top: Double, left: Double, bottom: Double, right: Double,
                contentWidth: Double, contentHeight: Double, docked: Bool) {
        safe = CGRect(x: max(0, left), y: max(0, top),
                      width: max(1, width - max(0, left) - max(0, right)),
                      height: max(1, height - max(0, top) - max(0, bottom)))
        let rail = docked && safe.width >= 360 ? 56.0 : 0.0
        leftRail = CGRect(x: safe.minX, y: safe.minY, width: rail, height: safe.height)
        rightRail = CGRect(x: safe.maxX - rail, y: safe.minY, width: rail, height: safe.height)
        let fit = Display.aspectFit(contentWidth: contentWidth, contentHeight: contentHeight,
                                    width: safe.width - rail * 2, height: safe.height)
        game = CGRect(x: safe.minX + rail + fit.0, y: safe.minY + fit.1, width: fit.2, height: fit.3)
    }

    public var pageSize: Int { max(2, min(10, Int(max(0, safe.height - 112) / 50) * 2)) }

    public func controlFrame(index: Int) -> CGRect {
        let rows = pageSize / 2
        let column = index / rows, row = index % rows
        let rail = column == 0 ? leftRail : rightRail
        return CGRect(x: rail.midX - 24, y: safe.minY + 56 + Double(row) * 50, width: 48, height: 44)
    }

    public func customFrame(x: Double, y: Double, width: Double) -> CGRect {
        let w = min(width, safe.width), h = 44.0
        return CGRect(x: safe.minX + min(1, max(0, x)) * max(0, safe.width - w),
                      y: safe.minY + min(1, max(0, y)) * max(0, safe.height - h), width: w, height: h)
    }
}

/// The displayed content's coordinates, independently of monitor mode/pixel scale.
public enum SurfacePointer {
    public static func fraction(x: Double, y: Double, width: Double, height: Double,
                                contentWidth: Double, contentHeight: Double, clamp: Bool) -> (Int32, Int32)? {
        let fit = Display.aspectFit(contentWidth: contentWidth, contentHeight: contentHeight, width: width, height: height)
        guard fit.2 > 0, fit.3 > 0 else { return nil }
        var px = x - fit.0, py = y - fit.1
        if clamp { px = min(max(px, 0), fit.2 - 0.001); py = min(max(py, 0), fit.3 - 0.001) }
        return Pointer.clientFraction(x: px, y: py, width: fit.2, height: fit.3)
    }
}
