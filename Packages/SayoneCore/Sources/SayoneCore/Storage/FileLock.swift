import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum FileLockError: Error, Equatable { case open(Int32), lock(Int32) }

public enum FileLock {
    /// Exclusive advisory lock held ONLY for the synchronous duration of `body`. Never `await` inside `body`.
    public static func withExclusiveLock<T>(at url: URL, _ body: () throws -> T) throws -> T {
        let fd = open(url.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { throw FileLockError.open(errno) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw FileLockError.lock(errno) }
        defer { _ = flock(fd, LOCK_UN) }
        return try body()
    }
}
