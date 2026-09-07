import Foundation
import CoreGraphics

public struct HandSample {
    public var point: CGPoint
    public var pinch: Double
    public var rightPinch: Double
    public var scroll: Bool
    public init(point: CGPoint, pinch: Double, rightPinch: Double = 1, scroll: Bool = false) {
        self.point = point; self.pinch = pinch; self.rightPinch = rightPinch; self.scroll = scroll
    }
}
public enum GestureAction: Equatable { case move(CGPoint), position(CGPoint), click, rightClick, down, up, scroll(Int32) }
public struct GestureEngine {
    public var sensitivity = 1.5
    public var smoothing = 0.7
    public var advanced = false
    public var screenMapping: ScreenMapping?
    public private(set) var aimingLocked = false
    private var resumeUntil = 0.0
    private var previous: CGPoint?
    private var filtered: CGPoint?
    private var armed = false
    private var pinchedAt: Double?
    private var dragging = false
    private var lastClick = -Double.infinity
    public init() {}
    public mutating func reset() -> [GestureAction] {
        let actions: [GestureAction] = dragging ? [.up] : []
        aimingLocked = false; resumeUntil = 0
        previous = nil; filtered = nil; armed = false; pinchedAt = nil; dragging = false
        return actions
    }
    public mutating func update(_ hand: HandSample, time: Double) -> [GestureAction] {
        var actions: [GestureAction] = []
        // Decide whether to freeze BEFORE consuming this frame's fingertip motion.
        let wasLocked = aimingLocked
        let nearPinch = hand.pinch < 0.40 || (advanced && hand.rightPinch < 0.40)
        let released = hand.pinch > 0.55 && (!advanced || hand.rightPinch > 0.55)
        if nearPinch && previous != nil { aimingLocked = true }
        if released { aimingLocked = false }
        if wasLocked && !aimingLocked { resumeUntil = time + 0.25 }
        let wasDragging = dragging
        if released {
            if let began = pinchedAt {
                if dragging { actions.append(.up) }
                else if advanced && time-began < 0.55 { actions.append(.click) }
                lastClick = time
            }
            pinchedAt = nil; dragging = false; armed = true
        } else if armed && time-lastClick >= 0.35 {
            if hand.pinch < 0.25 {
                armed = false; pinchedAt = time
                if !advanced { actions.append(.click); lastClick = time }
            } else if advanced && hand.rightPinch < 0.25 {
                armed = false; actions.append(.rightClick); lastClick = time
            }
        }
        if advanced, let began = pinchedAt, !dragging, time-began >= 0.55, hand.pinch < 0.45 {
            dragging = true; actions.append(.down)
        }
        if aimingLocked && !dragging { return actions }
        if wasLocked && !aimingLocked { return actions }
        if dragging && !wasDragging { resumeUntil = time + 0.25; return actions }
        let old = filtered ?? hand.point
        let baseAlpha = 1 - min(0.95, max(0, smoothing))
        let alpha = time < resumeUntil ? min(0.18, baseAlpha) : baseAlpha
        let point = CGPoint(x: old.x + (hand.point.x-old.x)*alpha, y: old.y + (hand.point.y-old.y)*alpha)
        filtered = point
        if let previous {
            let delta = CGPoint(x: (point.x-previous.x)*sensitivity, y: (point.y-previous.y)*sensitivity)
            if advanced && hand.scroll && pinchedAt == nil {
                let amount = Int32(max(-40, min(40, -delta.y*800)))
                if amount != 0 { actions.append(.scroll(amount)) }
            } else if let screenMapping { actions.append(.position(screenMapping.normalized(point))) }
            else { actions.append(.move(delta)) }
        }
        previous = point
        return actions
    }
}
