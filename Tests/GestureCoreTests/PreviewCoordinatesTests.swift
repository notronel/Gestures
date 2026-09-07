import XCTest
import CoreGraphics
@testable import GestureCore
final class PreviewCoordinatesTests: XCTestCase {
    func testNoSecondHorizontalFlip() {
        let point = PreviewCoordinates.topLeft(CGPoint(x: 0.8,y: 0.75))
        XCTAssertEqual(point, CGPoint(x: 0.8,y: 0.25))
        XCTAssertGreaterThan(point.x, 0.5)
    }
    func testLetterboxUsesActualImageDimensions() {
        XCTAssertEqual(PreviewCoordinates.aspectFit(CGSize(width: 640,height: 480), in: CGSize(width: 572,height: 240)), CGRect(x: 126,y: 0,width: 320,height: 240))
        XCTAssertEqual(PreviewCoordinates.aspectFit(CGSize(width: 1920,height: 1080), in: CGSize(width: 320,height: 240)), CGRect(x: 0,y: 30,width: 320,height: 180))
    }
    func testPreviewAndCalibrationHaveSameHandDirection() {
        let mapping = ScreenMapping()
        let left = mapping.normalized(PreviewCoordinates.topLeft(CGPoint(x: 0.25,y: 0.5)))
        let right = mapping.normalized(PreviewCoordinates.topLeft(CGPoint(x: 0.75,y: 0.5)))
        XCTAssertEqual(left.x, 0); XCTAssertEqual(right.x, 1)
    }
}
