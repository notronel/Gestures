import XCTest
import CoreGraphics
@testable import GestureCore
final class GestureEngineTests: XCTestCase {
    func sample(_ pinch: Double) -> HandSample { HandSample(point: CGPoint(x: 0.5,y: 0.5), pinch: pinch) }
    func testRequiresOpenHandAndDebounces() {
        var engine = GestureEngine()
        XCTAssertFalse(engine.update(sample(0.1), time: 0).contains(.click))
        _ = engine.update(sample(0.6), time: 0.1)
        XCTAssertTrue(engine.update(sample(0.1), time: 0.2).contains(.click))
        XCTAssertFalse(engine.update(sample(0.1), time: 0.3).contains(.click))
        _ = engine.update(sample(0.6), time: 0.4)
        XCTAssertFalse(engine.update(sample(0.1), time: 0.5).contains(.click))
        XCTAssertTrue(engine.update(sample(0.1), time: 0.9).contains(.click))
    }
    func testTrackingLossReleasesDragAndDisarms() {
        var engine = GestureEngine(); engine.advanced = true
        _ = engine.update(sample(0.6), time: 0)
        _ = engine.update(sample(0.1), time: 1)
        XCTAssertTrue(engine.update(sample(0.1), time: 1.6).contains(.down))
        XCTAssertEqual(engine.reset(), [.up])
        XCTAssertFalse(engine.update(sample(0.1), time: 2).contains(.down))
        XCTAssertEqual(engine.reset(), [])
    }
    func testReacquisitionDoesNotJump() {
        var engine = GestureEngine()
        XCTAssertFalse(engine.update(sample(0.6), time: 0).contains { if case .move = $0 { return true }; return false })
        _ = engine.reset()
        XCTAssertFalse(engine.update(HandSample(point: .zero, pinch: 0.6), time: 1).contains { if case .move = $0 { return true }; return false })
    }
    func testAdvancedClickOnRelease() {
        var engine = GestureEngine(); engine.advanced = true
        _ = engine.update(sample(0.6), time: 0)
        XCTAssertFalse(engine.update(sample(0.1), time: 1).contains(.click))
        XCTAssertTrue(engine.update(sample(0.6), time: 1.2).contains(.click))
    }
}
