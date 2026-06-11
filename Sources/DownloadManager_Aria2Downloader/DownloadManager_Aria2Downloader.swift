import DownloadManager
import DownloadManagerBasic
import Foundation
import libaria2

private let aria2ActiveStatus = 0
private let aria2WaitingStatus = 1
private let aria2PausedStatus = 2
private let aria2CompleteStatus = 3
private let aria2ErrorStatus = 4
private let aria2RemovedStatus = 5

public enum Aria2DownloaderSupport {
    public static var version: String {
        DMAria2Version()
    }

    public static let defaultProtocols: [ProtocolType] = [.magnet, .torrent, .ftp]
    public static let allAria2Protocols: [ProtocolType] = [.magnet, .torrent, .ftp, .http]
}

public struct Aria2DownloaderConfiguration: Sendable, Equatable {
    public var pollingInterval: TimeInterval
    public var continuePartialDownloads: Bool
    public var allowOverwrite: Bool
    public var autoFileRenaming: Bool
    public var sessionOptions: [String: String]
    public var downloadOptions: [String: String]

    public init(
        pollingInterval: TimeInterval = 0.25,
        continuePartialDownloads: Bool = true,
        allowOverwrite: Bool = true,
        autoFileRenaming: Bool = false,
        sessionOptions: [String: String] = [:],
        downloadOptions: [String: String] = [:]
    ) {
        self.pollingInterval = pollingInterval
        self.continuePartialDownloads = continuePartialDownloads
        self.allowOverwrite = allowOverwrite
        self.autoFileRenaming = autoFileRenaming
        self.sessionOptions = sessionOptions
        self.downloadOptions = downloadOptions
    }
}

public final class DownloadManager_Aria2Downloader: Downloader, @unchecked Sendable {
    public let supportProtocols: [ProtocolType]

    private let task: any DownloadTaskProtocol
    private let delegate: any DownloaderDelegate
    private let configuration: Aria2DownloaderConfiguration
    private let lock = NSRecursiveLock()
    private var session: DMAria2Session?
    private var gid: String?
    private var runTask: Task<Void, Never>?
    private var currentState: DownloaderState = .initial
    private var terminalStateSent = false

    public var state: DownloaderState {
        get async {
            locked { currentState }
        }
    }

    public init(
        task: any DownloadTaskProtocol,
        delegate: any DownloaderDelegate,
        configuration: Aria2DownloaderConfiguration = .init(),
        supportProtocols: [ProtocolType] = Aria2DownloaderSupport.defaultProtocols
    ) {
        self.task = task
        self.delegate = delegate
        self.configuration = configuration
        self.supportProtocols = supportProtocols
    }

    public func start() async {
        do {
            if locked({ session != nil }) {
                try resumeExistingDownload()
            } else {
                try createSessionAndAddDownload()
            }
            startRunLoopIfNeeded()
            await updateState(.downloading)
        } catch {
            await fail(error)
        }
    }

    public func pause() async {
        do {
            if let sessionAndGID = lockedSessionAndGID() {
                try sessionAndGID.session.pauseDownload(withGID: sessionAndGID.gid, force: true)
            }
            await updateState(.paused)
        } catch {
            await fail(error)
        }
    }

    public func resume() async {
        await start()
    }

    public func cancel() async {
        do {
            if let sessionAndGID = lockedSessionAndGID() {
                try sessionAndGID.session.removeDownload(withGID: sessionAndGID.gid, force: true)
            }
            await stopRunLoopAndFinalize(force: true)
            await updateState(.stop)
        } catch {
            await fail(error)
        }
    }

    public func cleanup() async {
        await stopRunLoopAndFinalize(force: true)
    }

    private func createSessionAndAddDownload() throws {
        let newSession = try DMAria2Session(options: configuration.sessionOptions)
        var outputGID: NSString?
        let options = aria2DownloadOptions()

        if task.url.isFileURL, task.url.pathExtension.lowercased() == "torrent" {
            try newSession.addTorrent(atPath: task.url.path, webSeedURIs: [], options: options, gid: &outputGID)
        } else {
            try newSession.addURI(task.url.absoluteString, options: options, gid: &outputGID)
        }

        guard let outputGID else {
            throw DownloadError.networkError("aria2 did not return a download GID.")
        }

        locked {
            session = newSession
            gid = outputGID as String
            terminalStateSent = false
        }
    }

    private func resumeExistingDownload() throws {
        if let sessionAndGID = lockedSessionAndGID() {
            try sessionAndGID.session.unpauseDownload(withGID: sessionAndGID.gid)
        }
    }

    private func aria2DownloadOptions() -> [String: String] {
        var options = configuration.downloadOptions
        let isMagnet = task.url.scheme?.lowercased() == "magnet"
        let outputDirectory = isMagnet ? task.destinationURL.path : task.destinationURL.deletingLastPathComponent().path

        options["dir"] = outputDirectory
        if !isMagnet {
            options["out"] = task.destinationURL.lastPathComponent
        }
        options["continue"] = configuration.continuePartialDownloads ? "true" : "false"
        options["allow-overwrite"] = configuration.allowOverwrite ? "true" : "false"
        options["auto-file-renaming"] = configuration.autoFileRenaming ? "true" : "false"
        options["max-connection-per-server"] = String(max(1, task.taskConfigure.maxConcurrentChunks))
        options["split"] = String(max(1, task.taskConfigure.maxConcurrentChunks))
        if let timeout = task.taskConfigure.timeoutInterval {
            options["timeout"] = String(max(1, Int(timeout.rounded(.up))))
        }
        return options
    }

    private func startRunLoopIfNeeded() {
        locked {
            guard runTask == nil else { return }
            runTask = Task { [weak self] in
                await self?.runLoop()
            }
        }
    }

    private func runLoop() async {
        while !Task.isCancelled {
            guard let sessionAndGID = lockedSessionAndGID() else {
                return
            }

            var runError: NSError?
            let result = sessionAndGID.session.run(.once, error: &runError)
            if result < 0 {
                await fail(runError ?? DownloadError.networkError("aria2 run failed with code \(result)."))
                return
            }

            do {
                let status = try sessionAndGID.session.status(forGID: sessionAndGID.gid)
                await publish(status: status)
                if await handleTerminalStatus(status, session: sessionAndGID.session) {
                    return
                }
            } catch {
                if !locked({ terminalStateSent }) {
                    await fail(error)
                }
                return
            }

            try? await Task.sleep(nanoseconds: UInt64(configuration.pollingInterval * 1_000_000_000))
        }
    }

    private func publish(status: [String: Any]) async {
        let completed = int64Value(status["completedLength"])
        let total = int64Value(status["totalLength"])
        await delegate.downloader(
            self,
            task: task,
            didUpdateProgress: DownloadProgress(downloadedBytes: completed, totalBytes: total)
        )
        if let speed = doubleValue(status["downloadSpeed"]) {
            await updateTaskSpeed(bytesPerSecond: speed, completedBytes: completed, totalBytes: total)
        }
    }

    private func handleTerminalStatus(_ status: [String: Any], session: DMAria2Session) async -> Bool {
        switch intValue(status["status"]) {
        case aria2ActiveStatus, aria2WaitingStatus:
            await updateState(.downloading)
            return false
        case aria2PausedStatus:
            await updateState(.paused)
            return false
        case aria2CompleteStatus:
            await stopRunLoopAndFinalize(session: session, force: false)
            await updateState(.completed)
            await delegate.downloader(self, didCompleteWith: task)
            return true
        case aria2ErrorStatus:
            let code = intValue(status["errorCode"])
            await stopRunLoopAndFinalize(session: session, force: true)
            await fail(DownloadError.networkError("aria2 download failed with code \(code)."))
            return true
        case aria2RemovedStatus:
            await stopRunLoopAndFinalize(session: session, force: true)
            await updateState(.stop)
            return true
        default:
            return false
        }
    }

    private func updateTaskSpeed(bytesPerSecond: Double, completedBytes: Int64, totalBytes: Int64) async {
        let remainingBytes = max(0, totalBytes - completedBytes)
        let remainingTime = bytesPerSecond > 0 ? Double(remainingBytes) / bytesPerSecond : TimeInterval.infinity
        if let task = task as? DownloadTask {
            task.update(speed: DownloadManagerSpeed(speed: bytesPerSecond, remainingTime: remainingTime))
        }
    }

    private func updateState(_ state: DownloaderState) async {
        let shouldSend = locked { () -> Bool in
            if terminalStateSent {
                return false
            }
            if isTerminal(state) {
                terminalStateSent = true
            }
            if currentState == state {
                return false
            }
            currentState = state
            return true
        }

        if shouldSend {
            await delegate.downloader(self, task: task, didUpdateState: state)
        }
    }

    private func fail(_ error: any Error) async {
        let downloadError = DownloadError.from(error)
        await stopRunLoopAndFinalize(force: true)
        await updateState(.failed(downloadError))
        await delegate.downloader(self, task: task, didFailWithError: downloadError)
    }

    private func stopRunLoopAndFinalize(force: Bool) async {
        let currentSession = locked { () -> DMAria2Session? in
            let value = session
            session = nil
            gid = nil
            runTask?.cancel()
            runTask = nil
            return value
        }
        await stopRunLoopAndFinalize(session: currentSession, force: force)
    }

    private func stopRunLoopAndFinalize(session: DMAria2Session?, force: Bool) async {
        guard let session else { return }
        try? session.shutdown(force)
        var finishError: NSError?
        _ = session.finish(&finishError)
    }

    private func lockedSessionAndGID() -> (session: DMAria2Session, gid: String)? {
        locked {
            guard let session, let gid else {
                return nil
            }
            return (session, gid)
        }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private func isTerminal(_ state: DownloaderState) -> Bool {
    switch state {
    case .completed, .failed, .stop:
        return true
    case .initial, .downloading, .paused:
        return false
    }
}

private func intValue(_ value: Any?) -> Int {
    if let number = value as? NSNumber {
        return number.intValue
    }
    if let value = value as? Int {
        return value
    }
    return 0
}

private func int64Value(_ value: Any?) -> Int64 {
    if let number = value as? NSNumber {
        return number.int64Value
    }
    if let value = value as? Int64 {
        return value
    }
    if let value = value as? Int {
        return Int64(value)
    }
    return 0
}

private func doubleValue(_ value: Any?) -> Double? {
    if let number = value as? NSNumber {
        return number.doubleValue
    }
    if let value = value as? Double {
        return value
    }
    return nil
}

public final class Aria2DownloaderFactory: NSObject, DownloaderFactory {
    public let configuration: Aria2DownloaderConfiguration
    public let supportedProtocols: [ProtocolType]

    public init(
        configuration: Aria2DownloaderConfiguration = .init(),
        supportedProtocols: [ProtocolType] = Aria2DownloaderSupport.defaultProtocols
    ) {
        self.configuration = configuration
        self.supportedProtocols = supportedProtocols
    }

    public func downloader(for type: ProtocolType, task: DownloadTaskProtocol, delegate: DownloaderDelegate) async throws -> Downloader {
        guard supportedProtocols.contains(type) else {
            throw DownloadError.serverNotSupported
        }
        return DownloadManager_Aria2Downloader(
            task: task,
            delegate: delegate,
            configuration: configuration,
            supportProtocols: supportedProtocols
        )
    }
}

public func registerAria2Downloader(
    supporting protocols: [ProtocolType] = Aria2DownloaderSupport.defaultProtocols,
    configuration: Aria2DownloaderConfiguration = .init()
) {
    let factory = Aria2DownloaderFactory(configuration: configuration, supportedProtocols: protocols)
    for type in protocols {
        DownloaderFactoryCenter.shared.register(factory: factory, for: type)
    }
}
