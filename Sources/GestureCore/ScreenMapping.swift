import CoreGraphics

/// A comfortable camera-space rectangle mapped to normalized display coordinates.
public struct ScreenMapping {
    public static let defaultArea = CGRect(x: 0.25, y: 0.2, width: 0.5, height: 0.6)
    public let area: CGRect
    public init(area: CGRect = ScreenMapping.defaultArea) { self.area = area }
    public static func calibrated(first: CGPoint, second: CGPoint) -> ScreenMapping? {
        let rect = CGRect(x: min(first.x, second.x), y: min(first.y, second.y), width: abs(second.x-first.x), height: abs(second.y-first.y))
        guard rect.width >= 0.12, rect.height >= 0.12,
              rect.minX >= 0, rect.minY >= 0, rect.maxX <= 1, rect.maxY <= 1 else { return nil }
        return ScreenMapping(area: rect)
    }
    public func normalized(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(1, max(0, (point.x-area.minX)/area.width)),
                y: min(1, max(0, (point.y-area.minY)/area.height)))
    }
    public func withGain(_ gain: Double) -> ScreenMapping {
        let gain = max(1, min(3, gain))
        let width = area.width/gain, height = area.height/gain
        return ScreenMapping(area: CGRect(x: area.midX-width/2, y: area.midY-height/2, width: width, height: height))
    }
    public static func position(_ normalized: CGPoint, in bounds: CGRect) -> CGPoint {
        CGPoint(x: bounds.minX + normalized.x*max(0, bounds.width-1),
                y: bounds.minY + normalized.y*max(0, bounds.height-1))
    }
}
