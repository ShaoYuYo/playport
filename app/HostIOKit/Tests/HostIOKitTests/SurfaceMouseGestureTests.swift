// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import HostIOKit

final class SurfaceMouseGestureTests: XCTestCase {
    typealias G = SurfaceMouseGesture
    func c(_ id: Int, _ x: Double, _ y: Double, _ phase: G.Phase) -> G.Contact {
        .init(id: id, x: x, y: y, phase: phase)
    }
    func p(_ x: Double, _ y: Double) -> G.Point { .init(x: x, y: y) }
    func beginPair(_ g: inout G) {
        _ = g.update([c(1, 100, 100, .began), c(2, 200, 100, .began)], now: 0)
    }
    func testSingleTapClicksOnLiftWithoutWaitingForHoldDeadline() {
        var g = G()
        XCTAssertEqual(g.update([c(1, 100, 100, .began)], now: 0), [.move(p(100,100))])
        XCTAssertEqual(g.deadline, 0.18)
        XCTAssertEqual(g.update([c(1, 102, 101, .ended)], now: 0.08), [.leftDown(p(102,101)), .leftUp(p(102,101))])
        XCTAssertNil(g.deadline)
        XCTAssertTrue(g.advance(now: 1).isEmpty)
    }
    func testDragReleasesAtLastMovedPointWithoutLiftMomentum() {
        var g = G(); _ = g.update([c(1, 100, 100, .began)], now: 0)
        XCTAssertEqual(g.update([c(1, 110, 100, .moved)], now: 0.03), [.leftDown(p(100,100)), .move(p(110,100))])
        XCTAssertNil(g.deadline)
        XCTAssertEqual(g.update([c(1, 120, 100, .ended)], now: 0.1), [.leftUp(p(110,100))])
        XCTAssertTrue(g.advance(now: 1).isEmpty)
        XCTAssertTrue(g.cancel().isEmpty)
    }

    func testLiftOnlyDisplacementCannotSynthesizeADrag() {
        var g = G(); _ = g.update([c(1,100,100,.began)], now: 0)
        XCTAssertEqual(g.update([c(1,150,100,.ended)], now: 0.1), [.leftDown(p(150,100)), .leftUp(p(150,100))])
        XCTAssertTrue(g.advance(now: 1).isEmpty)
    }

    func testHeldButtonReleaseDoesNotMoveToLiftCoordinate() {
        var g = G(); _ = g.update([c(1,100,100,.began)], now: 0)
        XCTAssertEqual(g.advance(now: 0.18), [.leftDown(p(100,100))])
        XCTAssertEqual(g.update([c(1,140,100,.ended)], now: 0.2), [.leftUp(p(100,100))])
        XCTAssertTrue(g.cancel().isEmpty)
    }
    func testStationaryHoldUsesOneDeadlineAndDoesNotRepeatDown() {
        var g = G(); _ = g.update([c(1, 100, 100, .began)], now: 0)
        XCTAssertTrue(g.advance(now: 0.1).isEmpty)
        XCTAssertEqual(g.advance(now: 0.18), [.leftDown(p(100,100))])
        XCTAssertNil(g.deadline); XCTAssertTrue(g.advance(now: 1).isEmpty)
        XCTAssertEqual(g.cancel(), [.leftUp(p(100,100))])
        XCTAssertTrue(g.cancel().isEmpty)
    }
    func testSimultaneousPairHasNoLeftClickRegardlessOfSetOrder() {
        for ids in [[1,2], [2,1]] {
            var g = G()
            let began = ids.map { c($0, $0 == 1 ? 100 : 200, 100, .began) }
            XCTAssertEqual(g.update(began, now: 0), [.move(p(100,100))])
            XCTAssertNil(g.deadline); XCTAssertTrue(g.advance(now: 1).isEmpty)
            XCTAssertEqual(g.update(ids.map { c($0, $0 == 1 ? 100 : 200, 100, .ended) }, now: 0.15), [.rightClick(p(150,100))])
        }
    }
    func testStaggeredPairLiftsDoNotBecomeLeftClick() {
        var g = G(); _ = g.update([c(1, 100, 100, .began)], now: 0)
        XCTAssertTrue(g.update([c(2, 200, 100, .began)], now: 0.05).isEmpty)
        XCTAssertTrue(g.update([c(1, 100, 100, .ended)], now: 0.1).isEmpty)
        XCTAssertEqual(g.update([c(2, 200, 100, .ended)], now: 0.2), [.rightClick(p(150,100))])
        XCTAssertTrue(g.advance(now: 1).isEmpty)
    }
    func testScrollCarriesSubNotchMovementAndNeverRightClicksOnLift() {
        var g = G(); beginPair(&g)
        for y in [92.0, 80.0] {
            XCTAssertTrue(g.update([c(1,100,y,.moved), c(2,200,y,.moved)], now: 0.1).isEmpty)
        }
        XCTAssertEqual(g.update([c(1,100,60,.moved), c(2,200,60,.moved)], now: 0.2), [.wheel(p(150,60), -120)])
        XCTAssertTrue(g.update([c(1,100,60,.ended)], now: 0.25).isEmpty)
        XCTAssertTrue(g.update([c(2,200,5,.moved)], now: 0.3).isEmpty)
        XCTAssertTrue(g.update([c(2,200,5,.ended)], now: 0.35).isEmpty)
    }
    func testNaturalScrollWorksInBothDirectionsAndPreservesRemainder() {
        var g = G(); beginPair(&g)
        XCTAssertEqual(g.update([c(1,100,150,.moved),c(2,200,150,.moved)], now: 0.1), [.wheel(p(150,150),120)])
        XCTAssertTrue(g.update([c(1,100,140,.moved),c(2,200,140,.moved)], now: 0.15).isEmpty)
        XCTAssertEqual(g.update([c(1,100,100,.moved),c(2,200,100,.moved)], now: 0.2), [.wheel(p(150,100),-120)])
        XCTAssertTrue(g.cancel().isEmpty)
    }
    func testOpposingFingerMovementAndLongHoldDoNotBecomeRightTap() {
        var g = G(); beginPair(&g)
        _ = g.update([c(1,90,100,.moved),c(2,210,100,.moved)], now: 0.1)
        XCTAssertTrue(g.update([c(1,90,100,.ended),c(2,210,100,.ended)], now: 0.2).isEmpty)
        beginPair(&g)
        XCTAssertTrue(g.update([c(1,100,100,.ended),c(2,200,100,.ended)], now: 1).isEmpty)
    }
    func testLateSecondFingerReleasesExistingLeftHoldWithoutRightTap() {
        var g = G(); _ = g.update([c(1,100,100,.began)], now: 0)
        _ = g.advance(now: 0.2)
        XCTAssertEqual(g.update([c(2,200,100,.began)], now: 0.21), [.leftUp(p(100,100))])
        XCTAssertTrue(g.update([c(1,100,100,.ended),c(2,200,100,.ended)], now: 0.3).isEmpty)
    }
    func testDelayedHoldTimerCannotTurnLateSecondFingerIntoRightClick() {
        var g = G(); _ = g.update([c(1,100,100,.began)], now: 0)
        // Simulate a busy main queue: the one-shot callback has not run yet.
        XCTAssertTrue(g.update([c(2,200,100,.began)], now: 1).isEmpty)
        XCTAssertTrue(g.advance(now: 1).isEmpty)
        XCTAssertTrue(g.update([c(1,100,100,.ended),c(2,200,100,.ended)], now: 1.1).isEmpty)
    }
    func testThirdOrReplacementFingerSuppressesEntireSequenceUntilLift() {
        var g = G(); beginPair(&g)
        _ = g.update([c(1,100,100,.ended)], now: 0.1)
        XCTAssertTrue(g.update([c(3,300,100,.began)], now: 0.15).isEmpty)
        XCTAssertTrue(g.update([c(2,200,100,.ended),c(3,300,100,.ended)], now: 0.2).isEmpty)
        XCTAssertEqual(g.update([c(4,100,100,.began)], now: 1), [.move(p(100,100))])
        XCTAssertEqual(g.update([c(4,100,100,.ended)], now: 1.1), [.leftDown(p(100,100)),.leftUp(p(100,100))])
    }
    func testCancellationAndFocusResetCannotCreateGhostClicks() {
        var g = G(); beginPair(&g)
        XCTAssertTrue(g.update([c(1,100,100,.cancelled)], now: 0.1).isEmpty)
        XCTAssertTrue(g.update([c(2,200,100,.ended)], now: 0.2).isEmpty)
        XCTAssertNil(g.deadline)
        _ = g.update([c(3,100,100,.began)], now: 1); _ = g.advance(now: 1.2)
        XCTAssertEqual(g.cancel(), [.leftUp(p(100,100))])
        XCTAssertTrue(g.update([c(3,100,100,.ended)], now: 1.3).isEmpty)
    }
    func testNonFiniteCoordinatesCancelAndWheelPacketsAreBounded() {
        var g = G(); beginPair(&g)
        XCTAssertEqual(g.update([c(1,100,10000,.moved),c(2,200,10000,.moved)], now: 0.1).count, 8)
        XCTAssertTrue(g.update([c(1,.nan,100,.moved)], now: 0.2).isEmpty)
        XCTAssertTrue(g.update([c(2,200,10000,.ended)], now: 0.3).isEmpty)
        XCTAssertNil(g.deadline)
    }
}
