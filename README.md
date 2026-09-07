# Gestures

A native macOS 13+ Swift app using Apple Vision and AVFoundation. Camera frames stay local; there are no network calls, recordings, or uploaded images.

## Build and run

Requires Xcode's Swift toolchain (Swift 5.9 or newer).

```sh
./scripts/build.sh
open dist/Gestures.app
```

Open `Package.swift` in Xcode to edit the project. Use the bundled app produced by the build script for camera permission testing: the script supplies the camera usage description and an ad-hoc signature. This is a local development build, not a notarized distribution. Rebuilding may require removing and re-adding its Accessibility entry.

## Start safely

The app launches paused, camera off, with **Practice mode enabled**. Click Enable Camera and approve camera access. Show one hand in good light, then press Start. Open your fingers before pinching; an already pinched hand cannot click on startup or after tracking loss.

Practice mode steers only the virtual crosshair. Pinch thumb and index over the blue target to score a hit; other clicks count as misses. The same calibrated absolute mapping, smoothing, and pinch logic powers practice and system control. The practice area matches the main display aspect ratio; results are not a screen accuracy benchmark.

To control the system pointer, stop, disable Practice mode, grant Gestures permission under System Settings → Privacy & Security → Accessibility, and press Start. Movement is absolute and constrained to the main display. The yellow camera rectangle maps corner-to-corner to that display, using macOS screen coordinates so Retina scaling is respected. Higher smoothing reduces movement noise but adds lag. Mouse speed now defaults to 1.5× (increased by 0.5 from the original 1.0× absolute mapping). Speed scales travel around the calibration center; at 1.5×, two-thirds of the calibrated width/height reaches the full display. The yellow outline shows this effective area. Changing speed pauses control; press Start again afterward.

**Command–Shift–Escape always pauses.** Stop, window close, sleep, and mode changes pause control. Losing usable tracking immediately suspends pointer actions and releases a drag; a 300 ms watchdog also handles stalled frames. Reacquisition resets movement and requires fingers to open before another click. Control resumes on reacquisition if Start remains active; use Stop to remain paused.

Camera permission: System Settings → Privacy & Security → Camera. If permission is denied, enable it there, toggle the camera off/on, or restart the app. Accessibility is unnecessary in practice mode. Camera capture continues while pointer control is paused; Turn Camera Off stops capture.

## Calibrate your reach

Keep Practice mode enabled. Enable Camera, choose Calibrate Reach, then capture your comfortable top-left and bottom-right index-finger positions. Each Capture Corner button gives a three-second countdown; hold still for the final half-second. Use your normal seated position and distance. Calibration pauses pointer actions and never starts them automatically.

The saved rectangle maps to the full main display. Outside that rectangle, the pointer clamps to the nearest edge. Practice uses the same normalized mapping and screen proportions. Press Start to test after calibration. Use Default Area to reset; Cancel preserves the previous calibration. Clear tracking is required during capture, and corners too close together are rejected. Calibration is saved locally; active state is never saved. Recalibrate if your camera position or seating distance changes.

## Optional gestures

Advanced gestures are experimental and off by default. Enabling them pauses control.

- Quick thumb/index pinch then release: left click.
- Hold thumb/index pinch for 0.55 seconds: drag; release to drop.
- Thumb/middle pinch: right click.
- Raise index and middle fingers with ring finger folded, then move vertically: scroll.

Aim locks before movement is processed when thumb/index distance falls below 0.40 palm lengths, then clicks below 0.25. Release above 0.55 unlocks aim with a brief eased transition. Basic-mode rearming uses only thumb and index, so a folded middle finger cannot block repeat left clicks. Advanced hold-to-drag begins at the locked point, then resumes movement. A visible pinch indicator reports the lock state. These thresholds remain subject to hands-on tuning.

Basic mode clicks immediately on pinch. Both modes use separate pinch/release thresholds and a 350 ms click debounce. Thresholds scale with palm size. Validate basic control in practice mode before enabling advanced gestures.

## Diagnostics and validation

Green dots show Vision landmarks above 0.5 confidence. The preview is mirrored. The confidence readout is the mean **of displayed landmarks**, not measured positional accuracy. FPS is a smoothed rate of processed video callbacks, including frames without a detected hand; it is not the camera's advertised capture FPS. Status identifies lost/usable tracking. Target hits/misses measure gesture interaction performance in the app.

True landmark accuracy requires reference ground truth. Stationary jitter measurement, recorded replay, and multi-display movement are deferred. Landmark overlay alignment and gesture thresholds still need hands-on camera testing on the target Mac.

```sh
swift test
```

Automated tests cover startup disarming, click debounce, drag release on tracking loss, reacquisition without jumping, and advanced click release. The initial release build and four gesture tests passed during development. Screen-mapping tests additionally cover full reach, clamping, display origins, invalid calibration, and absolute engine output. Live camera, macOS permissions, global hotkey delivery, and actual system pointer behavior require manual verification; they have not been activated automatically.

Manual acceptance: test open/pinch/hold/release in practice, hide your hand during a drag, stop during a drag, switch modes, interrupt the camera, and verify Command–Shift–Escape with another app focused before everyday use.

Vision API reference: https://developer.apple.com/documentation/vision/vndetecthumanhandposerequest
