import Darwin
import Foundation

func withFileLock<T>(rootURL: URL, operation: () throws -> T) throws -> T {
    do { try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true) } catch {
        throw CopilotError.storageUnavailable
    }
    let lockURL = rootURL.appendingPathComponent(".repository.lock")
    let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { throw CopilotError.storageUnavailable }
    defer { close(descriptor) }
    guard flock(descriptor, LOCK_EX) == 0 else { throw CopilotError.storageUnavailable }
    defer { flock(descriptor, LOCK_UN) }
    return try operation()
}

func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        #else
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        #endif
    } catch { throw CopilotError.storageUnavailable }
}
