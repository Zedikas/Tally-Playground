// swift-tools-version: 6.0
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "Tally Playground",
    platforms: [.iOS("26.0")],
    products: [
        .iOSApplication(
            name: "Tally",
            targets: ["AppModule"],
            bundleIdentifier: "com.samua.tally.playground",
            displayVersion: "2.0",
            bundleVersion: "23",
            appIcon: .placeholder(icon: .calculator),
            accentColor: .presetColor(.pink),
            supportedDeviceFamilies: [.pad, .phone],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "Sources/AppModule",
            resources: [
                .process("Resources/Assets.xcassets"),
                .process("Resources/Localizable.strings"),
                .copy("Resources/Tally2BuildMetadata.json")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
