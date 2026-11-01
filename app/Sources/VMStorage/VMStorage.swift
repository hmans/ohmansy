import Foundation
import Darwin

/// Owns the exclusive lock for a VM for as long as this object exists.
public final class VMStorage {
    public let directory: URL
    private let lockDescriptor: Int32

    public var disk: URL { directory.appendingPathComponent("disk.raw") }
    public var efi: URL { directory.appendingPathComponent("efi-vars") }
    public var macAddress: URL { directory.appendingPathComponent("mac-address") }

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let descriptor = open(directory.appendingPathComponent("lock").path,
                              O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw StorageError.alreadyRunning
        }
        lockDescriptor = descriptor
    }

    deinit { close(lockDescriptor) }

    /// Creates a sparse disk once. An existing disk is never resized or replaced.
    public func prepareDisk(size: Int64 = 64 * 1024 * 1024 * 1024) throws {
        guard size > 0 else { throw StorageError.invalidDisk }
        let descriptor = open(disk.path, O_CREAT | O_EXCL | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        if descriptor < 0 {
            guard errno == EEXIST else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            let values = try disk.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  (values.fileSize ?? 0) > 0 else { throw StorageError.invalidDisk }
            return
        }
        defer { close(descriptor) }
        guard ftruncate(descriptor, off_t(size)) == 0 else {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            unlink(disk.path)
            throw error
        }
    }
}

public enum StorageError: LocalizedError {
    case alreadyRunning, invalidDisk
    public var errorDescription: String? {
        switch self {
        case .alreadyRunning: "Another ohmansy process is using this VM."
        case .invalidDisk: "The VM disk is empty or is not a regular file. It has not been changed."
        }
    }
}
