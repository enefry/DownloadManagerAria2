# DownloadManagerAria2

Optional aria2-backed downloader for
[DownloadManager](https://github.com/enefry/DownloadManager).

This package keeps BitTorrent, magnet, FTP, and libaria2 integration outside
the core DownloadManager package so apps that only need HTTP downloads do not
pull the libaria2 binary or GPL-licensed components.

## Usage

Add this package only in products that need aria2-backed protocols:

```swift
.package(url: "https://github.com/enefry/DownloadManagerAria2.git", from: "0.1.0")
```

Then depend on:

```swift
.product(name: "DownloadManager_Aria2Downloader", package: "DownloadManagerAria2")
```

Register the downloader at app startup:

```swift
import DownloadManager_Aria2Downloader

registerAria2Downloader()
```

The default registration supports:

```swift
[.magnet, .torrent, .ftp]
```

HTTP support is available but not registered by default, so it does not replace
DownloadManager's normal HTTP downloader:

```swift
registerAria2Downloader(supporting: Aria2DownloaderSupport.allAria2Protocols)
```

## Local Development

When developing this package next to a local DownloadManager checkout, point
the manifest at that checkout and at a locally built libaria2 XCFramework:

```sh
scripts/build-libaria2-xcframework.sh

DOWNLOAD_MANAGER_PACKAGE_PATH=../DownloadManager \
LIBARIA2_XCFRAMEWORK_PATH=artifacts/libaria2/libaria2.xcframework \
swift test
```

The local checkout layout used by CI is:

```text
Utils/
  ConcurrencyCollection/
  DownloadManager/
  DownloadManagerAria2/
```

The sibling layout is currently required because DownloadManager itself uses a
local path dependency on `../ConcurrencyCollection`.

## Binary Artifact

The package consumes libaria2 as a SwiftPM remote binary target:

```swift
.binaryTarget(
    name: "libaria2",
    url: "https://github.com/enefry/DownloadManagerAria2/releases/download/...",
    checksum: "..."
)
```

The XCFramework zip is built and published by GitHub Actions. Generated
`artifacts/` and `dist/` directories are ignored and should not be committed.

The XCFramework contains:

- macOS arm64, minimum macOS 13.0
- iOS arm64, minimum iOS 15.0
- iOS Simulator arm64, minimum iOS 15.0

The libaria2 build is trimmed to system dynamic dependencies only and links the
ObjC wrapper into the same `libaria2.0.dylib`.

## Build And Verify libaria2

Build, validate, and package the XCFramework locally:

```sh
scripts/build-libaria2-xcframework.sh
scripts/verify-libaria2-xcframework.sh
scripts/package-libaria2-xcframework.sh
```

After packaging, update the remote binary target URL and checksum with:

```sh
scripts/update-libaria2-binary-target.sh \
  "https://github.com/enefry/DownloadManagerAria2/releases/download/libaria2-1.37.0/libaria2.xcframework.zip" \
  "$(cat dist/libaria2.xcframework.zip.checksum)"
```

The full rebuild requires Xcode command line tools, autotools, and Apple SDKs.
CI performs the same build/verify/package flow and uploads the zip/checksum as
workflow artifacts. The `Release libaria2` workflow can publish the release
asset and commit the updated `Package.swift`.

The build scripts fetch aria2 from upstream `release-1.37.0` into ignored
`third_party/aria2` when the source tree is not already present, then apply
the patches in `patches/aria2`.

## Licensing

aria2/libaria2 is GPL-2.0-or-later with an OpenSSL linking exception. Confirm
license compatibility before shipping this package in an app.
