import AVFoundation
import Vision
import CoreImage
import GestureCore

struct CameraFrame {
    let image: CGImage
    let landmarks: [CGPoint]
    let confidence: Float
    let sample: HandSample?
    let time: Double
}

final class Camera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    let queue = DispatchQueue(label: "Gestures.camera")
    var onFrame: ((CameraFrame) -> Void)?
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    var onStatus: ((String) -> Void)?
    private let request = VNDetectHumanHandPoseRequest()
    private var configured = false
    func start() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
            guard let self else { return }
            guard allowed else { self.onStatus?("Camera access denied. Enable Gestures in System Settings → Privacy & Security → Camera."); return }
            self.queue.async {
                do {
                    if !self.configured {
                        guard let device = AVCaptureDevice.default(for: .video) else { self.onStatus?("No camera found."); return }
                        let input = try AVCaptureDeviceInput(device: device)
                        self.session.beginConfiguration()
                        self.session.sessionPreset = .vga640x480
                        let output = AVCaptureVideoDataOutput()
                        output.alwaysDiscardsLateVideoFrames = true
                        output.setSampleBufferDelegate(self, queue: self.queue)
                        guard self.session.canAddInput(input), self.session.canAddOutput(output) else {
                            self.session.commitConfiguration(); self.onStatus?("Camera configuration failed."); return
                        }
                        self.session.addInput(input); self.session.addOutput(output)
                        if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
                            connection.automaticallyAdjustsVideoMirroring = false
                            connection.isVideoMirrored = false
                        }
                        self.session.commitConfiguration(); self.configured = true
                        self.request.maximumHandCount = 1
                    }
                    self.session.startRunning()
                    self.onStatus?("Camera ready — show one hand.")
                } catch { self.onStatus?("Camera error: \(error.localizedDescription)") }
            }
        }
    }
    func stop() { queue.async { self.session.stopRunning() } }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // Mirror physical pixels exactly once. Vision and preview use this SAME image.
        // No independently configured preview connection or second horizontal flip.
        let mirrored = CIImage(cvPixelBuffer: buffer).oriented(.upMirrored)
        guard let image = imageContext.createCGImage(mirrored, from: mirrored.extent) else { return }
        var landmarks: [CGPoint] = []
        var confidence: Float = 0
        var sample: HandSample?
        defer { onFrame?(CameraFrame(image: image, landmarks: landmarks, confidence: confidence, sample: sample, time: now)) }
        do {
            try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
            guard let hand = request.results?.first else { return }
            let points = try hand.recognizedPoints(.all)
            let visible = points.values.filter { $0.confidence > 0.5 }
            landmarks = visible.map { PreviewCoordinates.topLeft($0.location) }
            confidence = visible.isEmpty ? 0 : visible.map(\.confidence).reduce(0,+)/Float(visible.count)
            func point(_ joint: VNHumanHandPoseObservation.JointName) -> CGPoint? {
                guard let p = points[joint], p.confidence > 0.5 else { return nil }; return p.location
            }
            guard let index = point(.indexTip), let thumb = point(.thumbTip), let wrist = point(.wrist), let knuckle = point(.middleMCP) else { return }
            func distance(_ a: CGPoint, _ b: CGPoint) -> Double { hypot((a.x-b.x)*Double(image.width)/Double(image.height), a.y-b.y) }
            let scale = distance(wrist, knuckle)
            guard scale > 0.04 else { return }
            let middle = point(.middleTip)
            let ring = point(.ringTip)
            let scroll = middle.map { distance($0, wrist) > scale*1.5 } ?? false
            let foldedRing = ring.map { distance($0, wrist) < scale*1.35 } ?? false
            sample = HandSample(point: PreviewCoordinates.topLeft(index), pinch: distance(index, thumb)/scale,
                                 rightPinch: middle.map { distance($0, thumb)/scale } ?? 1,
                                 scroll: scroll && foldedRing && distance(index, wrist) > scale*1.5)
        } catch { landmarks = []; confidence = 0 }
    }
}
