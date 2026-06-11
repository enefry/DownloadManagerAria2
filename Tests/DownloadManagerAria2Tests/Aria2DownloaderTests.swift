import Combine
import DownloadManager
import DownloadManager_Aria2Downloader
import DownloadManagerBasic
import XCTest

final class Aria2DownloaderTests: XCTestCase {
    func testLibaria2VersionIsExposed() {
        XCTAssertEqual(Aria2DownloaderSupport.version, "1.37.0")
    }

    func testFactoryRejectsUnsupportedProtocol() async throws {
        let factory = Aria2DownloaderFactory(supportedProtocols: [.magnet])
        let task = TestDownloadTask(url: URL(string: "https://example.com/file.bin")!)
        let delegate = TestDownloaderDelegate()

        do {
            _ = try await factory.downloader(for: .http, task: task, delegate: delegate)
            XCTFail("Expected unsupported protocol to throw")
        } catch {
            XCTAssertTrue(error is DownloadError)
        }
    }

    func testFactoryCreatesMagnetDownloader() async throws {
        let factory = Aria2DownloaderFactory(supportedProtocols: [.magnet])
        let task = TestDownloadTask(url: URL(string: "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567")!)
        let delegate = TestDownloaderDelegate()
        let downloader = try await factory.downloader(for: .magnet, task: task, delegate: delegate)
        let state = await downloader.state

        XCTAssertEqual(downloader.supportProtocols, [.magnet])
        XCTAssertEqual(state, .initial)
    }

    func testFactoryCreatesTorrentDownloader() async throws {
        let factory = Aria2DownloaderFactory(supportedProtocols: [.torrent])
        let task = TestDownloadTask(url: FileManager.default.temporaryDirectory.appendingPathComponent("fixture.torrent"))
        let delegate = TestDownloaderDelegate()
        let downloader = try await factory.downloader(for: .torrent, task: task, delegate: delegate)
        let state = await downloader.state

        XCTAssertEqual(downloader.supportProtocols, [.torrent])
        XCTAssertEqual(state, .initial)
    }
}

private final class TestDownloadTask: DownloadTaskProtocol, @unchecked Sendable {
    let identifier = "aria2-test"
    let taskConfigure = DownloadTaskConfiguration()
    let url: URL
    let destinationURL: URL
    let downloadedBytes: Int64 = 0
    let totalBytes: Int64 = -1
    let startTime: TimeInterval = 0
    let state: TaskState = .pending
    let progress = DownloadProgress(downloadedBytes: 0, totalBytes: -1)
    let progressPublisher = Empty<DownloadProgress, Never>().eraseToAnyPublisher()
    let speedPublisher = Empty<DownloadManagerSpeed, Never>().eraseToAnyPublisher()
    let statePublisher = Empty<TaskState, Never>().eraseToAnyPublisher()

    init(url: URL) {
        self.url = url
        destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent("aria2-test")
    }
}

private final class TestDownloaderDelegate: DownloaderDelegate {
    func downloader(_ downloader: any Downloader, task: DownloadTaskProtocol, didUpdateProgress progress: DownloadProgress) async {}
    func downloader(_ downloader: any Downloader, task: DownloadTaskProtocol, didUpdateState state: DownloaderState) async {}
    func downloader(_ downloader: any Downloader, didCompleteWith task: DownloadTaskProtocol) async {}
    func downloader(_ downloader: any Downloader, task: DownloadTaskProtocol, didFailWithError error: any Error) async {}
}
