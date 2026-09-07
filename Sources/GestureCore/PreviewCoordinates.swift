import CoreGraphics

public enum PreviewCoordinates {
    /// Input is Vision's bottom-left coordinates for the already-mirrored image.
    /// Flip only Y. This same result drives landmarks, calibration and pointer.
    public static func topLeft(_ vision: CGPoint) -> CGPoint {
        CGPoint(x: vision.x, y: 1-vision.y)
    }
    public static func aspectFit(_ image: CGSize, in view: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0 else { return .zero }
        let scale = min(view.width/image.width, view.height/image.height)
        let size = CGSize(width: image.width*scale, height: image.height*scale)
        return CGRect(x: (view.width-size.width)/2, y: (view.height-size.height)/2, width: size.width, height: size.height)
    }
}
