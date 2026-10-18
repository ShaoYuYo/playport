// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Direct-touch mouse arbitration, independent of UIKit delivery/set ordering.
/// A single tap clicks on lift with no post-lift delay; motion starts a drag,
/// and a one-shot hold deadline supports a stationary mouse press. A second
/// finger before that press consumes the whole sequence as right-tap/scroll.
public struct SurfaceMouseGesture: Sendable {
    public struct Point: Equatable, Sendable {
        public var x: Double, y: Double
        public init(x: Double, y: Double) { self.x = x; self.y = y }
        fileprivate func distance(_ p: Self) -> Double { hypot(x - p.x, y - p.y) }
        fileprivate var finite: Bool { x.isFinite && y.isFinite }
    }
    public enum Phase: Sendable { case began, moved, ended, cancelled }
    public struct Contact: Sendable {
        public var id: Int, point: Point, phase: Phase
        public init(id: Int, x: Double, y: Double, phase: Phase) {
            self.id = id; point = Point(x: x, y: y); self.phase = phase
        }
    }
    public enum Action: Equatable, Sendable {
        case move(Point), leftDown(Point), leftUp(Point), rightClick(Point), wheel(Point, Int32)
    }
    public static let holdDelay = 0.18
    public static let movementThreshold = 8.0
    public static let tapDuration = 0.4
    public static let pointsPerNotch = 40.0
    public private(set) var deadline: Double?
    private var points: [Int: Point] = [:]
    private var first: Int?
    private var origin = Point(x: 0, y: 0), last = Point(x: 0, y: 0)
    private var leftHeld = false, paired = false, draining = false, invalid = false
    private var pairOrigins: [Int: Point] = [:]
    private var pairStart = 0.0, pairAnchor = Point(x: 0, y: 0)
    private var pairLast = Point(x: 0, y: 0), pairPoint = Point(x: 0, y: 0)
    private var tapEligible = false, scrolling = false, remainder = 0.0
    public init() {}

    public mutating func update(_ changes: [Contact], now: Double) -> [Action] {
        guard now.isFinite else { return cancel() }
        if changes.contains(where: { $0.phase == .cancelled || !$0.point.finite }) { return cancel() }
        var ended = Set<Int>()
        let wasEmpty = points.isEmpty
        // Beginnings are installed together, before deciding whether this is
        // a single press. Two fingers in one UIKit batch cannot click left.
        for c in changes.sorted(by: { $0.id < $1.id }) {
            if c.phase == .began {
                if points[c.id] == nil { points[c.id] = c.point }
            } else if points[c.id] != nil {
                points[c.id] = c.point
                if c.phase == .ended { ended.insert(c.id) }
            }
        }
        guard !points.isEmpty else { return [] }
        var out: [Action] = []
        if wasEmpty, let id = points.keys.min(), let p = points[id] {
            first = id; origin = p; last = p; deadline = now + Self.holdDelay
            out.append(.move(p))
        }
        let live = points.filter { !ended.contains($0.key) }
        if points.count > 2 || (paired && points.keys.contains(where: { pairOrigins[$0] == nil })) {
            invalid = true; deadline = nil
            if leftHeld { out.append(.leftUp(last)); leftHeld = false }
        }
        if !invalid && !paired && live.count == 2 {
            // A delayed main-thread timer must not turn a long single-finger
            // hold into a right tap when the second finger finally arrives.
            tapEligible = !leftHeld && (deadline.map { now < $0 } ?? false)
            paired = true; deadline = nil
            if leftHeld { out.append(.leftUp(last)); leftHeld = false }
            pairOrigins = live; pairStart = now
            pairAnchor = centroid(live); pairLast = pairAnchor; pairPoint = pairAnchor
        }
        if !invalid && paired {
            // Movement of either finger cancels a right tap, including opposing
            // movements whose centroid does not move. One remaining finger is
            // consumed until lift and cannot become a new left click/drag.
            for (id, p) in points {
                if let start = pairOrigins[id], p.distance(start) >= Self.movementThreshold { tapEligible = false }
            }
            if !draining && points.count == 2 {
                let p = centroid(points)
                pairPoint = p
                let dy = p.y - pairLast.y
                if !scrolling && abs(p.y - pairAnchor.y) >= Self.movementThreshold {
                    scrolling = true; tapEligible = false
                    remainder = p.y - pairAnchor.y
                } else if scrolling { remainder += dy }
                pairLast = p
                if scrolling {
                    // Windows +120 scrolls up. Fingers moving down pull content
                    // down (natural touch scrolling); keep fractions between events.
                    let n = Int(max(-8, min(8, remainder / Self.pointsPerNotch)).rounded(.towardZero))
                    if n != 0 {
                        for _ in 0..<abs(n) { out.append(.wheel(p, n > 0 ? 120 : -120)) }
                        remainder -= Double(n) * Self.pointsPerNotch
                    }
                    remainder = max(-320, min(320, remainder))
                }
            }
            if !ended.isEmpty { draining = true }
        } else if !invalid, let first, let p = points[first] {
            last = p
            if !leftHeld && p.distance(origin) >= Self.movementThreshold {
                leftHeld = true; deadline = nil; out.append(.leftDown(origin))
            }
            if ended.contains(first) {
                if !leftHeld { out.append(.leftDown(p)) }
                out.append(.leftUp(p)); leftHeld = false; deadline = nil
            } else if leftHeld { out.append(.move(p)) }
        }
        for id in ended { points.removeValue(forKey: id) }
        if points.isEmpty {
            if paired && !invalid && tapEligible && !scrolling && now - pairStart <= Self.tapDuration {
                out.append(.rightClick(pairPoint))
            }
            self = Self()
        }
        return out
    }

    public mutating func advance(now: Double) -> [Action] {
        guard let deadline, now.isFinite, now >= deadline, !paired, !invalid, points.count == 1 else { return [] }
        self.deadline = nil; leftHeld = true
        return [.leftDown(last)]
    }

    public mutating func cancel() -> [Action] {
        let out: [Action] = leftHeld ? [.leftUp(last)] : []
        self = Self()
        return out
    }

    private func centroid(_ points: [Int: Point]) -> Point {
        let n = Double(points.count)
        // Sort for deterministic floating-point summation across UIKit sets.
        return points.keys.sorted().reduce(Point(x: 0, y: 0)) { result, id in
            let p = points[id]!
            return Point(x: result.x + p.x / n, y: result.y + p.y / n)
        }
    }
}
