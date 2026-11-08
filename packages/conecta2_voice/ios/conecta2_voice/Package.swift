// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "conecta2_voice",
    platforms: [.iOS(.v15)],
    products: [.library(name: "conecta2-voice", targets: ["conecta2_voice"])],
    targets: [
        .binaryTarget(name: "WhisperNative", path: "WhisperNative.xcframework"),
        .target(name: "VoiceBridge", dependencies: ["WhisperNative"], publicHeadersPath: "include"),
        .target(name: "conecta2_voice", dependencies: ["VoiceBridge"])
    ],
    cxxLanguageStandard: .cxx17
)
