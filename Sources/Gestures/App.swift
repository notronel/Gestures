import SwiftUI
import AVFoundation
import ApplicationServices
import Carbon
import GestureCore

final class Controller: ObservableObject {
    @Published var active = false
    @Published var status = "Paused — enable camera to preview."
    @Published var tracking = false
    @Published var cameraEnabled = false
    @Published var controlArea = ScreenMapping.defaultArea
    @Published var calibrationStep = 0
    @Published var calibrationMessage = "Use the outlined area, or calibrate your comfortable reach."
    @Published var capturingCorner = false
    @Published var displayBounds = CGDisplayBounds(CGMainDisplayID())
    private var firstCorner: CGPoint?
    private var captureDeadline: Double?
    private var cornerSamples: [(Double, CGPoint)] = []
    var practiceSize: CGSize {
        CGSize(width: 572, height: 572 * displayBounds.height / max(1, displayBounds.width))
    }
    @Published var speed = 1.5 { didSet { pause() } }
    @Published var pinchLocked = false
    var effectiveArea: CGRect { ScreenMapping(area: controlArea).withGain(speed).area }
    @Published var smoothing = 0.7
    @Published var advanced = false { didSet { pause() } }
    @Published var practice = true { didSet { pause() } }
    @Published var previewFrame: CameraFrame?
    @Published var confidence: Float = 0
    @Published var fps = 0.0
    @Published var virtualPointer = CGPoint(x: 286, y: 90)
    @Published var target = CGPoint(x: 140, y: 90)
    @Published var hits = 0
    @Published var misses = 0
    let camera = Camera()
    private var engine = GestureEngine()
    private var lastFrame = 0.0
    private var dragging = false
    private var timer: Timer?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var observers: [NSObjectProtocol] = []
    init() {
        if let values = UserDefaults.standard.array(forKey: "controlArea") as? [Double], values.count == 4,
           let mapping = ScreenMapping.calibrated(first: CGPoint(x: values[0], y: values[1]), second: CGPoint(x: values[2], y: values[3])) {
            controlArea = mapping.area
        }
        camera.onStatus = { [weak self] message in DispatchQueue.main.async { self?.status = message } }
        camera.onFrame = { [weak self] frame in
            DispatchQueue.main.async {
                guard let self, self.cameraEnabled, ProcessInfo.processInfo.systemUptime-frame.time < 0.25 else { return }
                self.previewFrame = frame
                self.confidence = frame.confidence
                self.receive(frame.sample, time: frame.time)
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.updateCalibration()
            if ProcessInfo.processInfo.systemUptime-self.lastFrame > 0.3 { self.loseTracking() }
            if self.active && !self.practice && !AXIsProcessTrusted() { self.pause(); self.status = "Accessibility permission required." }
        }
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            let controller = Unmanaged<Controller>.fromOpaque(context).takeUnretainedValue()
            controller.pause(); return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let result = RegisterEventHotKey(UInt32(kVK_Escape), UInt32(cmdKey | shiftKey), EventHotKeyID(signature: 0x47535452, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        if result != noErr { status = "Emergency shortcut unavailable; restart before using pointer control." }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.pause() })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in self?.pause(); self?.camera.stop() })
    }
    func beginCalibration() {
        pause()
        guard cameraEnabled else { calibrationMessage = "Enable the camera first."; return }
        calibrationStep = 1; firstCorner = nil
        calibrationMessage = "Place your index fingertip at your comfortable TOP-LEFT reach. Capture gives you 3 seconds."
    }
    func captureCorner() {
        guard calibrationStep > 0, !capturingCorner else { return }
        cornerSamples = []; captureDeadline = ProcessInfo.processInfo.systemUptime + 3
        capturingCorner = true
    }
    private func updateCalibration() {
        guard let deadline = captureDeadline else { return }
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        if remaining > 0 {
            calibrationMessage = "Hold your fingertip at the \(calibrationStep == 1 ? "TOP-LEFT" : "BOTTOM-RIGHT") corner: \(Int(ceil(remaining)))"
            return
        }
        capturingCorner = false; captureDeadline = nil
        let points = cornerSamples.filter { $0.0 > deadline-0.5 }.map { $0.1 }
        guard tracking, points.count >= 5 else { calibrationMessage = "Not enough clear tracking. Show your hand and capture this corner again."; return }
        let point = CGPoint(x: points.map(\.x).reduce(0,+)/Double(points.count), y: points.map(\.y).reduce(0,+)/Double(points.count))
        if calibrationStep == 1 {
            firstCorner = point; calibrationStep = 2
            calibrationMessage = "Now place your fingertip at your comfortable BOTTOM-RIGHT reach and capture."
        } else if let firstCorner, let mapping = ScreenMapping.calibrated(first: firstCorner, second: point) {
            controlArea = mapping.area; calibrationStep = 0
            UserDefaults.standard.set([controlArea.minX, controlArea.minY, controlArea.maxX, controlArea.maxY], forKey: "controlArea")
            calibrationMessage = "Calibration saved. Your comfortable reach maps to the full main display. Press Start to test."
        } else {
            calibrationMessage = "Corners are too close together. Capture farther diagonally from the first corner."
        }
    }
    func resetCalibration() {
        pause(); controlArea = ScreenMapping.defaultArea
        UserDefaults.standard.removeObject(forKey: "controlArea")
        calibrationMessage = "Default control area restored."
    }
    func toggleCamera() {
        pause(); cameraEnabled.toggle()
        if cameraEnabled { camera.start() } else { camera.stop(); status = "Camera off"; tracking = false; previewFrame = nil }
    }
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    func start() {
        guard calibrationStep == 0 else { status = "Finish calibration or press Cancel before starting."; return }
        displayBounds = CGDisplayBounds(CGMainDisplayID())
        guard hotKey != nil else { status = "Emergency shortcut registration failed. Restart the app."; return }
        guard practice || AXIsProcessTrusted() else { requestAccessibility(); status = "Allow Gestures in Privacy & Security → Accessibility, then press Start."; return }
        guard cameraEnabled, tracking else { status = "Enable the camera and show a hand before starting."; return }
        _ = engine.reset(); active = true; status = "Active — ⌘⇧Esc to pause"
    }
    func pause() {
        captureDeadline = nil; capturingCorner = false; calibrationStep = 0
        if dragging {
            CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: CGEvent(source: nil)?.location ?? .zero, mouseButton: .left)?.post(tap: .cghidEventTap)
            dragging = false
        }
        perform(engine.reset()); pinchLocked = false; active = false
        status = "Paused — pointer control off"
    }
    private func loseTracking() {
        if tracking { perform(engine.reset()) }
        tracking = false; pinchLocked = false
        if ProcessInfo.processInfo.systemUptime-lastFrame > 0.3 {
            previewFrame = nil; confidence = 0; fps = 0
        }
    }
    private func receive(_ sample: HandSample?, time: Double) {
        guard cameraEnabled, ProcessInfo.processInfo.systemUptime-time < 0.25 else { loseTracking(); return }
        if lastFrame > 0 && time > lastFrame { fps = fps*0.8 + (1/(time-lastFrame))*0.2 }; lastFrame = time
        guard let sample else { loseTracking(); return }
        tracking = true
        if capturingCorner {
            cornerSamples.append((time, sample.point))
            cornerSamples.removeAll { $0.0 < time-0.6 }
        }
        guard active else { return }
        guard practice || AXIsProcessTrusted() else { pause(); return }
        engine.screenMapping = ScreenMapping(area: effectiveArea); engine.smoothing = smoothing; engine.advanced = advanced
        perform(engine.update(sample, time: time))
        pinchLocked = engine.aimingLocked
    }
    private func perform(_ actions: [GestureAction]) {
        for action in actions {
            if practice {
                switch action {
                case .position(let point): virtualPointer = ScreenMapping.position(point, in: CGRect(origin: .zero, size: practiceSize))
                case .move(let delta): virtualPointer = CGPoint(x: max(0,min(572,virtualPointer.x+delta.x*572)), y: max(0,min(180,virtualPointer.y+delta.y*180)))
                case .click, .rightClick:
                    if hypot(virtualPointer.x-target.x, virtualPointer.y-target.y) <= 24 {
                        hits += 1; target = CGPoint(x: Double.random(in: 30...542), y: Double.random(in: 30...max(31, practiceSize.height-30)))
                    } else { misses += 1 }
                default: break
                }
                continue
            }
            let current = CGEvent(source: nil)?.location ?? .zero
            func mouse(_ type: CGEventType, _ button: CGMouseButton = .left, _ point: CGPoint? = nil) {
                CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point ?? current, mouseButton: button)?.post(tap: .cghidEventTap)
            }
            switch action {
            case .position(let normalized):
                let point = ScreenMapping.position(normalized, in: displayBounds)
                mouse(dragging ? .leftMouseDragged : .mouseMoved, .left, point)
            case .move(let delta):
                // Main display coordinates use a top-left origin, matching CGEvent.
                let bounds = CGDisplayBounds(CGMainDisplayID())
                let point = CGPoint(x: max(bounds.minX, min(bounds.maxX-1, current.x+delta.x*bounds.width)), y: max(bounds.minY, min(bounds.maxY-1, current.y+delta.y*bounds.height)))
                mouse(dragging ? .leftMouseDragged : .mouseMoved, .left, point)
            case .click: mouse(.leftMouseDown); mouse(.leftMouseUp)
            case .rightClick: mouse(.rightMouseDown, .right); mouse(.rightMouseUp, .right)
            case .down: dragging = true; mouse(.leftMouseDown)
            case .up: mouse(.leftMouseUp); dragging = false
            case .scroll(let amount): CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: amount, wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
            }
        }
    }
}
struct CameraPreview: View {
    let frame: CameraFrame?
    let controlArea: CGRect
    var body: some View {
        Canvas { context, size in
            guard let frame else { return }
            let rect = PreviewCoordinates.aspectFit(CGSize(width: frame.image.width, height: frame.image.height), in: size)
            context.draw(Image(decorative: frame.image, scale: 1, orientation: .up), in: rect)
            let area = CGRect(x: rect.minX+controlArea.minX*rect.width, y: rect.minY+controlArea.minY*rect.height, width: controlArea.width*rect.width, height: controlArea.height*rect.height)
            context.stroke(Path(area), with: .color(.yellow), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            for landmark in frame.landmarks {
                let p = CGPoint(x: rect.minX+landmark.x*rect.width, y: rect.minY+landmark.y*rect.height)
                context.fill(Path(ellipseIn: CGRect(x: p.x-3, y: p.y-3, width: 6, height: 6)), with: .color(.green))
            }
        }.allowsHitTesting(false)
    }
}
@main struct GesturesApp: App {
    @StateObject private var model = Controller()
    var body: some Scene {
        WindowGroup("Gestures") {
            ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Text("Gestures").font(.largeTitle.bold()); Spacer(); Label(model.active ? "Active" : "Paused", systemImage: model.active ? "cursorarrow.motionlines" : "pause.circle").foregroundColor(model.active ? .green : .secondary) }
                CameraPreview(frame: model.previewFrame, controlArea: model.calibrationStep > 0 ? model.controlArea : model.effectiveArea)
                    .frame(height: 240).background(Color.black).cornerRadius(12)
                Text("Processed frames: \(model.fps, specifier: "%.0f")/s · Mean visible landmark confidence: \(model.confidence, specifier: "%.2f") (not accuracy)").font(.caption)
                Text("Full main display · \(Int(model.displayBounds.width)) × \(Int(model.displayBounds.height)) screen points").font(.caption)
                Text(model.calibrationMessage).font(.callout)
                HStack {
                    if model.calibrationStep == 0 {
                        Button("Calibrate Reach") { model.beginCalibration() }
                        Button("Use Default Area") { model.resetCalibration() }
                    } else {
                        Button(model.capturingCorner ? "Capturing…" : "Capture Corner (3s)") { model.captureCorner() }.disabled(model.capturingCorner)
                        Button("Cancel") { model.pause(); model.calibrationMessage = "Calibration cancelled. Previous area retained." }
                    }
                }
                Toggle("Practice mode — virtual pointer only", isOn: $model.practice)
                if model.practice {
                    ZStack(alignment: .topLeading) {
                        Color.gray.opacity(0.12)
                        Circle().fill(Color.blue.opacity(0.5)).frame(width: 48, height: 48).position(model.target)
                        Image(systemName: "plus").foregroundStyle(.orange).position(model.virtualPointer)
                    }.frame(width: model.practiceSize.width, height: model.practiceSize.height).clipped()
                    HStack { Text("Target hits: \(model.hits) · Misses: \(model.misses)"); Button("Reset score") { model.hits = 0; model.misses = 0 } }
                }
                Label(model.tracking ? "Hand tracked" : "No hand — pointer actions suspended", systemImage: model.tracking ? "hand.raised.fill" : "hand.raised.slash")
                Text(model.status).font(.callout).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(model.cameraEnabled ? "Turn Camera Off" : "Enable Camera") { model.toggleCamera() }
                    Button(model.active ? "Stop" : "Start") { if model.active { model.pause() } else { model.start() } }.buttonStyle(.borderedProminent)
                    Button("Accessibility Permission") { model.requestAccessibility() }
                }
                Text("The yellow camera area maps corner-to-corner to your main display. A smaller calibrated area requires less hand travel.").font(.caption)
                Text(model.pinchLocked ? "Pinch detected — aim held steady" : "Aim with index · bring thumb toward index to click").font(.caption)
                HStack { Text("Mouse speed").frame(width: 95, alignment: .leading); Slider(value: $model.speed, in: 1...3, step: 0.1); Text("\(model.speed, specifier: "%.1f")×") }
                HStack { Text("Smoothing").frame(width: 95, alignment: .leading); Slider(value: $model.smoothing, in: 0...0.9); Text(model.smoothing, format: .percent.precision(.fractionLength(0))).monospacedDigit() }
                Toggle("Enable experimental scrolling, right-click and drag", isOn: $model.advanced)
                Text(model.advanced ? "Quick thumb–index pinch and release: click. Hold pinch: drag; release to drop. Thumb–middle pinch: right-click. Raise index and middle with ring folded, then move vertically: scroll." : "Move your index finger to steer. Pinch thumb and index to click; separate fully before clicking again.").font(.callout)
                Text("Emergency pause: ⌘⇧Esc · Camera processing stays on this Mac").font(.footnote).foregroundStyle(.secondary)
            }.padding(24).frame(width: 620)
                } .frame(width: 620, height: 820)
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in model.pause() }
        }.windowResizability(.contentSize)
    }
}
