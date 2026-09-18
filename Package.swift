// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CatFace",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "FaceEngine", targets: ["FaceEngine"]),
        .library(name: "CatFaceUI", targets: ["CatFaceUI"]),
        .executable(name: "face-preview", targets: ["FacePreview"]),
    ],
    targets: [
        // Pure geometry. No UI frameworks, so it builds and tests anywhere,
        // including Linux CI.
        .target(name: "FaceEngine"),

        // SwiftUI rendering layer. Compiles to an empty module where SwiftUI
        // is unavailable, so `swift build` still succeeds off-platform.
        .target(name: "CatFaceUI", dependencies: ["FaceEngine"]),

        // Dumps SVG stills of the rig. Useful for tuning the face without
        // launching the app.
        .executableTarget(name: "FacePreview", dependencies: ["FaceEngine"]),

        .testTarget(name: "FaceEngineTests", dependencies: ["FaceEngine"]),
    ]
)
