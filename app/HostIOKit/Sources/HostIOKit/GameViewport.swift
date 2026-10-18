// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Keep the render view and controls in one coordinate space. Side rails are
/// outside the game's view and inside the window's camera/home-indicator insets.
public struct GameViewport: Sendable {
    public static let edgeToEdgeKey = "display.edgeToEdge"
    public let safe: CGRect
    public let game: CGRect
    public let leftRail: CGRect
    public let rightRail: CGRect

    public init(width: Double, height: Double, top: Double, left: Double, bottom: Double, right: Double,
                contentWidth: Double, contentHeight: Double, docked: Bool, edgeToEdge: Bool = false) {
        safe = CGRect(x: max(0, left), y: max(0, top),
                      width: max(1, width - max(0, left) - max(0, right)),
                      height: max(1, height - max(0, top) - max(0, bottom)))
        let rail = docked && safe.width >= 360 ? 56.0 : 0.0
        leftRail = CGRect(x: safe.minX, y: safe.minY, width: rail, height: safe.height)
        rightRail = CGRect(x: safe.maxX - rail, y: safe.minY, width: rail, height: safe.height)
        // Rendering may use the full window while hit targets retain their
        // separate camera/home-indicator-safe canvas. Do not shrink the game
        // vertically just to keep a button away from the home indicator.
        let canvas = edgeToEdge ? CGRect(x: 0, y: 0, width: max(1, width), height: max(1, height)) : safe
        let renderRail = edgeToEdge ? 0 : rail
        let fit = Display.aspectFit(contentWidth: contentWidth, contentHeight: contentHeight,
                                    width: canvas.width - renderRail * 2, height: canvas.height)
        game = CGRect(x: canvas.minX + renderRail + fit.0, y: canvas.minY + fit.1, width: fit.2, height: fit.3)
    }

    public var pageSize: Int { max(2, min(10, Int(max(0, safe.height - 112) / 50) * 2)) }

    /// Prefer a side letterbox inside the control-safe canvas, at the outer
    /// edge and away from rounded corners. A wider camera-free side wins.
    /// If the picture fills the screen, use the less obstructed safe edge.
    public func menuFrame(contentWidth: Double, contentHeight: Double) -> CGRect {
        let fit = Display.aspectFit(contentWidth: contentWidth, contentHeight: contentHeight,
                                    width: game.width, height: game.height)
        let picture = CGRect(x: game.minX + fit.0, y: game.minY + fit.1, width: fit.2, height: fit.3)
        let leftSpace = picture.minX - safe.minX, rightSpace = safe.maxX - picture.maxX
        let size = min(44, min(safe.width, safe.height))
        let x = rightSpace >= leftSpace ? safe.maxX - size : safe.minX
        return CGRect(x: x, y: safe.midY - size / 2, width: size, height: size)
    }

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

    /// Inverse of customFrame: dragging uses the same actual safe canvas and
    /// button width as gameplay, so saving/reopening does not move a button.
    public func customPosition(origin: CGPoint, width: Double) -> CGPoint {
        let w = min(width, safe.width)
        return CGPoint(x: min(1, max(0, (origin.x - safe.minX) / max(1, safe.width - w))),
                       y: min(1, max(0, (origin.y - safe.minY) / max(1, safe.height - 44))))
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
