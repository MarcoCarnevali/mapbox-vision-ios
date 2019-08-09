import Foundation

private let memoryLimit: MemoryByte = 300 * .mByte
private let networkingMemoryLimit: MemoryByte = 30 * .mByte
private let updatingInterval = 1 * .hour

final class RecordSynchronizer: Synchronizable {
    enum RecordSynchronizerError: LocalizedError {
        case syncFileCreationFail(URL)
        case noRequestedFiles([RecordFileType], URL)
    }

    struct Dependencies {
        let networkClient: NetworkClient
        let deviceInfo: DeviceInfoProvidable
        let archiver: Archiver
        let fileManager: FileManagerProtocol
    }

    private enum State {
        case idle
        case syncing
        case stopping

        var isIdle: Bool {
            return self == .idle
        }

        var isSyncing: Bool {
            return self == .syncing
        }

        var isStopping: Bool {
            return self == .stopping
        }
    }

    weak var delegate: SyncDelegate?

    private let dependencies: Dependencies
    private var dataSource: RecordDataSource?
    private let queue = DispatchQueue(label: "com.mapbox.RecordSynchronizer")
    private let syncFileName = ".synced"
    private let telemetryFileName = "telemetry"
    private let imagesSubpath = "images"
    private let imagesFileName = "images"
    private let quota = RecordingQuota(memoryQuota: networkingMemoryLimit, refreshInterval: updatingInterval)

    private var state: State = .idle {
        didSet {
            guard let delegate = delegate else { return }
            switch state {
            case .idle:
                DispatchQueue.main.async(execute: delegate.syncStopped)
            case .syncing:
                DispatchQueue.main.async(execute: delegate.syncStarted)
            case .stopping:
                break
            }
        }
    }

    private var hasPendingRequest: Bool = false

    init(_ dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func set(dataSource: RecordDataSource) {
        self.dataSource = dataSource
    }

    func sync() {
        queue.async { [weak self] in
            guard let self = self else { return }

            if !self.state.isIdle {
                self.hasPendingRequest = true
                return
            }

            self.executeSync()
        }
    }

    private func executeSync() {
        hasPendingRequest = false
        state = .syncing

        guard let directories = dataSource?.recordDirectories else { return }
        clean(directories)

        uploadTelemetry(directories) { [weak self] in
            guard let self = self, self.canContinue() else { return }

            self.uploadImages(directories) { [weak self] in
                guard let self = self, self.canContinue() else { return }

                self.uploadVideos(directories) { [weak self] in
                    guard let self = self, self.canContinue() else { return }

                    self.state = .idle
                }
            }
        }
    }

    private func isMarkAsSynced(url: URL) -> Bool {
        guard let content = try? dependencies.fileManager.contentsOfDirectory(atPath: url.path) else {
            return false
        }
        return content.contains(syncFileName)
    }

    private func getFiles(_ url: URL, types: [RecordFileType]) throws -> [URL] {
        let extensions = types.map { $0.fileExtension }
        let files = try dependencies.fileManager.contentsOfDirectory(at: url)
            .filter { extensions.contains($0.pathExtension) }
        guard !files.isEmpty else { throw RecordSynchronizerError.noRequestedFiles(types, url) }

        return files
    }

    private func uploadTelemetry(_ directories: [URL], completion: @escaping () -> Void) {
        uploadArchivedFiles(directories, types: [.bin, .json], archiveName: telemetryFileName, eachDirectoryCompletion: { [weak self] dir, remoteDir in
            do {
                try self?.markAsSynced(dir: dir, remoteDir: remoteDir)
            } catch {
                print(error)
            }
        }, completion: completion)
    }

    private func uploadImages(_ directories: [URL], completion: @escaping () -> Void) {
        uploadArchivedFiles(directories, types: [.image], subPath: imagesSubpath, archiveName: imagesFileName, completion: completion)
    }

    private func uploadArchivedFiles(
        _ directories: [URL],
        types: [RecordFileType],
        subPath: String? = nil,
        archiveName: String,
        eachDirectoryCompletion: ((_ dir: URL, _ remoteDir: String) -> Void)? = nil,
        completion: @escaping () -> Void
    ) {
        let group = DispatchGroup()

        for dir in directories {
            group.enter()

            let destination = dir.appendingPathComponent(archiveName).appendingPathExtension(RecordFileType.archive.fileExtension)

            do {
                if !dependencies.fileManager.fileExists(atPath: destination.path) {
                    var sourceDir = dir
                    if let subPath = subPath {
                        sourceDir.appendPathComponent(subPath, isDirectory: true)
                    }
                    let files = try getFiles(sourceDir, types: types)
                    try dependencies.archiver.archive(files, destination: destination)
                    files.forEach(dependencies.fileManager.remove)
                }

                try self.quota.reserve(memoryToReserve: dependencies.fileManager.fileSize(at: destination))
            } catch {
                print("Directory \(dir) failed to archive. Error: \(error.localizedDescription)")
                group.leave()
                continue
            }

            let remoteDir = createRemoteDirName(dir)

            dependencies.networkClient.upload(file: destination, toFolder: remoteDir) { [weak self] error in
                if let error = error {
                    print(error)
                } else {
                    self?.dependencies.fileManager.remove(item: destination)
                    eachDirectoryCompletion?(dir, remoteDir)
                }
                group.leave()
            }
        }

        group.notify(queue: queue, execute: completion)
    }

    private func uploadVideos(_ directories: [URL], completion: @escaping () -> Void) {
        let group = DispatchGroup()

        let fileSize = dependencies.fileManager.fileSize
        let sorted = directories
            .flatMap { (try? self.getFiles($0, types: [.video])) ?? [] }
            .sorted { fileSize($0) < fileSize($1) }

        for file in sorted {
            group.enter()

            do {
                try quota.reserve(memoryToReserve: fileSize(file))
            } catch {
                print("Quota reservation error: \(error.localizedDescription)")
                group.leave()
                continue
            }

            let remoteDir = createRemoteDirName(file.deletingLastPathComponent())

            dependencies.networkClient.upload(file: file, toFolder: remoteDir) { [weak self] error in
                if let error = error {
                    print(error)
                } else {
                    self?.dependencies.fileManager.remove(item: file)
                }
                group.leave()
            }
        }

        group.notify(queue: queue, execute: completion)
    }

    private func clean(_ directories: [URL]) {
        directories
            .sortedByCreationDate
            .filter(isMarkAsSynced)
            .reduce(([URL](), MemoryByte(0))) { base, url in
                let dirSize = dependencies.fileManager.sizeOfDirectory(at: url)

                let totalDirSize = base.1 + dirSize
                if totalDirSize > memoryLimit || dirSize == 0 {
                    return (base.0 + [url], totalDirSize)
                } else {
                    return (base.0, totalDirSize)
                }
            }.0
            .forEach(dependencies.fileManager.remove)
    }

    private func markAsSynced(dir: URL, remoteDir: String) throws {
        guard createSyncFile(in: dir) != nil else {
            throw RecordSynchronizerError.syncFileCreationFail(dir)
        }
    }

    private func createRemoteDirName(_ dir: URL) -> String {
        return Path([
            dir.lastPathComponent,
            Locale.current.identifier,
            dependencies.deviceInfo.id,
            dependencies.deviceInfo.platformName,
        ]).components.joined(separator: "_")
    }

    private func createSyncFile(in url: URL) -> URL? {
        let syncFilePath = url.appendingPathComponent(syncFileName).path
        guard dependencies.fileManager.createFile(atPath: syncFilePath, contents: nil) else {
            return nil
        }
        return URL(fileURLWithPath: syncFilePath, relativeTo: url)
    }

    private func canContinue() -> Bool {
        if state.isStopping {
            if hasPendingRequest {
                executeSync()
            } else {
                state = .idle
            }
            return false
        }
        return true
    }

    func stopSync() {
        state = state.isSyncing ? .stopping : .idle
        dependencies.networkClient.cancel()
    }
}
