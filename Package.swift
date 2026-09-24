// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "AulaKeyboard",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AulaKit", targets: ["AulaKit"]),
        .executable(name: "aula", targets: ["aula"]),
        .executable(name: "AulaStudio", targets: ["AulaStudio"]),
    ],
    targets: [
        .target(
            name: "AulaKit",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        .executableTarget(name: "aula", dependencies: ["AulaKit"]),
        .executableTarget(name: "AulaStudio", dependencies: ["AulaKit"]),
    ]
)
