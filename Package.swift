// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Gestures", platforms: [.macOS(.v13)], products: [.executable(name: "Gestures", targets: ["Gestures"])], targets: [.target(name: "GestureCore"), .executableTarget(name: "Gestures", dependencies: ["GestureCore"]), .testTarget(name: "GestureCoreTests", dependencies: ["GestureCore"])])
