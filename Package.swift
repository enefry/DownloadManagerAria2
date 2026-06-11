// swift-tools-version:5.9
import Foundation
import PackageDescription

let downloadManagerDependency: Package.Dependency
if let localPath = ProcessInfo.processInfo.environment["DOWNLOAD_MANAGER_PACKAGE_PATH"], !localPath.isEmpty {
    downloadManagerDependency = .package(path: localPath)
} else {
    downloadManagerDependency = .package(url: "https://github.com/enefry/DownloadManager.git", branch: "master")
}

let defaultLibaria2BinaryURL = "https://github.com/enefry/DownloadManagerAria2/releases/download/libaria2-1.37.0/libaria2.xcframework.zip"
let defaultLibaria2BinaryChecksum = "0000000000000000000000000000000000000000000000000000000000000000"

let libaria2Target: Target
if let localPath = ProcessInfo.processInfo.environment["LIBARIA2_XCFRAMEWORK_PATH"], !localPath.isEmpty {
    libaria2Target = .binaryTarget(
        name: "libaria2",
        path: localPath
    )
} else {
    libaria2Target = .binaryTarget(
        name: "libaria2",
        url: defaultLibaria2BinaryURL,
        checksum: defaultLibaria2BinaryChecksum
    )
}

let package = Package(
    name: "DownloadManagerAria2",
    platforms: [
        .iOS(.v15),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "DownloadManager_Aria2Downloader",
            targets: ["DownloadManager_Aria2Downloader"]
        )
    ],
    dependencies: [
        downloadManagerDependency
    ],
    targets: [
        .target(
            name: "DownloadManager_Aria2Downloader",
            dependencies: [
                .product(name: "DownloadManagerBasic", package: "DownloadManager"),
                .product(name: "DownloadManager", package: "DownloadManager"),
                .target(name: "libaria2")
            ],
            path: "Sources/DownloadManager_Aria2Downloader"
        ),
        libaria2Target,
        .testTarget(
            name: "DownloadManagerAria2Tests",
            dependencies: [
                "DownloadManager_Aria2Downloader",
                .product(name: "DownloadManagerBasic", package: "DownloadManager"),
                .product(name: "DownloadManager", package: "DownloadManager")
            ]
        )
    ]
)
