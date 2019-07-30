import Foundation

final class RecordingQuota {
    enum Keys {
        static let recordingMemoryQuotaKey = "recordingMemoryQuota"
        static let lastResetTimeKey = "lastResetTimeKey"
    }

    private enum RecordingQuotaError: LocalizedError {
        case memoryQuotaExceeded
    }

    // MARK: - Private properties

    private let memoryQuota: MemoryByte
    private let refreshInterval: TimeInterval

    private var lastResetTime: Date {
        get {
            let defaults = UserDefaults.standard
            if let time = defaults.object(forKey: Keys.lastResetTimeKey) as? Date {
                return time
            } else {
                let time = Date()
                defaults.set(time, forKey: Keys.lastResetTimeKey)
                return time
            }
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.lastResetTimeKey)
        }
    }

    private var cachedCurrentQuota: MemoryByte {
        get {
            if let quota = UserDefaults.standard.object(forKey: Keys.recordingMemoryQuotaKey) as? MemoryByte {
                return quota
            } else {
                let quota = memoryQuota
                UserDefaults.standard.set(quota, forKey: Keys.recordingMemoryQuotaKey)
                return quota
            }
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.recordingMemoryQuotaKey)
        }
    }

    // MARK: - Lifecycle

    init(memoryQuota: MemoryByte, refreshInterval: TimeInterval) {
        self.memoryQuota = memoryQuota
        self.refreshInterval = refreshInterval
    }

    // MARK: - Functions

    func reserve(memoryToReserve: MemoryByte) throws {
        var currentQuota = cachedCurrentQuota

        let now = Date()
        if now.timeIntervalSince(lastResetTime) >= refreshInterval {
            currentQuota = memoryQuota
            lastResetTime = now
        }

        guard currentQuota >= memoryToReserve else { throw RecordingQuotaError.memoryQuotaExceeded }
        cachedCurrentQuota = currentQuota - memoryToReserve
    }
}
