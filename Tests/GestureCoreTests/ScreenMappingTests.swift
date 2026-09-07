import XCTest
import CoreGraphics
@testable import GestureCore
final class ScreenMappingTests: XCTestCase {
    func testComfortableCornersReachFullScreen() {
        let mapping = ScreenMapping.calibrated(first: CGPoint(x: 0.3,y: 0.25), second: CGPoint(x: 0.7,y: 0.75))!
        XCTAssertEqual(mapping.normalized(CGPoint(x: 0.3,y: 0.25)), .zero)
        XCTAssertEqual(mapping.normalized(CGPoint(x: 0.7,y: 0.75)), CGPoint(x: 1,y: 1))
        let center = mapping.normalized(CGPoint(x: 0.5,y: 0.5))
        XCTAssertEqual(center.x, 0.5, accuracy: 0.000001)
        XCTAssertEqual(center.y, 0.5, accuracy: 0.000001)
        XCTAssertEqual(mapping.normalized(CGPoint(x: 1,y: 0)), CGPoint(x: 1,y: 0))
    }
    func testBoundsOriginAndLastPixel() {
        XCTAssertEqual(ScreenMapping.position(CGPoint(x: 1,y: 1), in: CGRect(x: -1920,y: 0,width: 1920,height: 1080)), CGPoint(x: -1,y: 1079))
    }
    func testInvalidCalibrationRejected() {
        XCTAssertNil(ScreenMapping.calibrated(first: .zero, second: CGPoint(x: 0.01,y: 0.9)))
        XCTAssertNil(ScreenMapping.calibrated(first: CGPoint(x: -0.1,y: 0), second: CGPoint(x: 0.9,y: 0.9)))
    }
    func testEngineEmitsAbsolutePosition() {
        var engine = GestureEngine(); engine.screenMapping = ScreenMapping(); engine.smoothing = 0
        _ = engine.update(HandSample(point: CGPoint(x: 0.5,y: 0.5), pinch: 1), time: 0)
        let actions = engine.update(HandSample(point: CGPoint(x: 0.75,y: 0.8), pinch: 1), time: 0.1)
        XCTAssertTrue(actions.contains(.position(CGPoint(x: 1,y: 1))))
    }
}
