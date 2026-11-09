// swift-tools-version: 6.2
import PackageDescription

// Exercise the same state and Photos integration code on macOS without a photo library.
let package = Package(
    name: "CleanPhotoLogic",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CleanPhotoLogic",
            path: "CleanPhoto",
            exclude: ["CleanPhoto-Mac.entitlements", "Assets.xcassets", "Views", "CleanPhotoApp.swift",
                      "ContentView.swift", "BatchReviewView.swift", "EmptyStateView.swift",
                      "PhotoGridView.swift", "SwipeCardView.swift", "SwipeContainerView.swift"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "CleanPhotoLogicTests", dependencies: ["CleanPhotoLogic"], path: "Tests")
    ],
    swiftLanguageModes: [.v5]
)
