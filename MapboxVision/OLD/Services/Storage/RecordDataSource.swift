import Foundation

protocol RecordDataSource {
    var baseURL: URL { get }
    var recordDirectories: [URL] { get }
    func removeFile(at url: URL)
}

extension RecordDataSource {
    var recordDirectories: [URL] {
        return baseURL.subDirectories
    }
    
    func removeFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

final class SyncRecordDataSource: RecordDataSource {
    var baseURL: URL {
        return URL(fileURLWithPath: LocationInDocumentDir.recordingsDir.path, isDirectory: true)
    }
}

final class ShowcaseRecordDataSource: RecordDataSource {
    var baseURL: URL {
        return URL(fileURLWithPath: LocationInDocumentDir.showcaseDir.path, isDirectory: true)
    }
}

final class CachedRecordDataSource: RecordDataSource {
    let dataSource: RecordDataSource
    
    init(dataSource: RecordDataSource) {
        self.dataSource = dataSource
    }
    
    private lazy var cachedBaseURL: URL = {
        return dataSource.baseURL
    }()
    var baseURL: URL {
        return cachedBaseURL
    }
    
    private lazy var cachedRecordDirectories: [URL] = {
        return dataSource.recordDirectories
    }()
    var recordDirectories: [URL] {
        return cachedRecordDirectories
    }
}
