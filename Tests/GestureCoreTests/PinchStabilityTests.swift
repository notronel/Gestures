import XCTest
import CoreGraphics
@testable import GestureCore
final class PinchStabilityTests: XCTestCase {
    func hand(_ x: Double, _ pinch: Double, middle: Double = 1) -> HandSample {
        HandSample(point: CGPoint(x: x, y: 0.5), pinch: pinch, rightPinch: middle)
    }
    func testPinchApproachAndClickCannotMoveAim() {
        var engine = GestureEngine(); engine.screenMapping = ScreenMapping(); engine.smoothing = 0
        _ = engine.update(hand(0.5, 0.8), time: 0)
        _ = engine.update(hand(0.5, 0.8), time: 0.1)
        XCTAssertEqual(engine.update(hand(0.6, 0.35), time: 0.2), [])
        XCTAssertTrue(engine.aimingLocked)
        XCTAssertEqual(engine.update(hand(0.7, 0.1), time: 0.3), [.click])
        XCTAssertEqual(engine.update(hand(0.72, 0.1), time: 0.4), [])
        XCTAssertEqual(engine.update(hand(0.7, 0.8), time: 0.5), [])
        let actions = engine.update(hand(0.7, 0.8), time: 0.53)
        guard case .position(let position) = actions.first else { return XCTFail("Expected resumed movement") }
        XCTAssertLessThan(position.x, 0.65, "Release should ease in rather than jump directly to 0.9")
    }
    func testLeftPinchRearmsWithoutMiddleFinger() {
        var engine = GestureEngine()
        _ = engine.update(hand(0.5, 0.8, middle: 0.1), time: 0)
        XCTAssertEqual(engine.update(hand(0.5, 0.1, middle: 0.1), time: 0.1), [.click])
        _ = engine.update(hand(0.5, 0.8, middle: 0.1), time: 0.2)
        XCTAssertEqual(engine.update(hand(0.5, 0.1, middle: 0.1), time: 0.6), [.click])
    }
    func testDragStartsAtLockedPointThenMovesAndReleases() {
        var engine = GestureEngine(); engine.advanced = true
        _ = engine.update(hand(0.5, 0.8), time: 0)
        _ = engine.update(hand(0.6, 0.1), time: 0.1)
        XCTAssertEqual(engine.update(hand(0.7, 0.1), time: 0.7), [.down])
        XCTAssertTrue(engine.update(hand(0.72, 0.1), time: 0.73).contains { if case .move = $0 { return true }; return false })
        XCTAssertEqual(engine.update(hand(0.75, 0.8), time: 0.8), [.up])
        XCTAssertEqual(engine.reset(), [])
    }
    func testGainIncreasesTravelByHalfAndRetainsEdges() {
        let mapping = ScreenMapping().withGain(1.5)
        XCTAssertEqual(mapping.normalized(CGPoint(x: 0.55, y: 0.5)).x, 0.65, accuracy: 0.000001)
        XCTAssertEqual(mapping.normalized(CGPoint(x: 0.25, y: 0.2)), .zero)
        XCTAssertEqual(mapping.normalized(CGPoint(x: 0.75, y: 0.8)), CGPoint(x: 1,y: 1))
    }
}
