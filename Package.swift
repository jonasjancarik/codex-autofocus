// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "codex-autofocus",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "codex-autofocus", targets: ["CodexAutofocus"]),
        .executable(name: "CodexAutofocusMenuBar", targets: ["CodexAutofocusMenuBar"]),
        .library(name: "CodexAutofocusCore", targets: ["CodexAutofocusCore"])
    ],
    targets: [
        .target(name: "CodexAutofocusCore"),
        .executableTarget(
            name: "CodexAutofocus",
            dependencies: ["CodexAutofocusCore"]
        ),
        .executableTarget(
            name: "CodexAutofocusMenuBar",
            dependencies: ["CodexAutofocusCore"]
        ),
        .testTarget(
            name: "CodexAutofocusCoreTests",
            dependencies: ["CodexAutofocusCore"]
        )
    ]
)
