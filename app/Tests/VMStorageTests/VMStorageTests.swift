import Foundation
import Testing
@testable import VMStorage

@Test func preservesExistingDiskAndReleasesLock() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var storage: VMStorage? = try VMStorage(directory: directory)
    try storage!.prepareDisk(size: 1024 * 1024)
    let disk = storage!.disk
    let handle = try FileHandle(forWritingTo: disk)
    try handle.write(contentsOf: Data("persistent guest data".utf8))
    try handle.close()
    #expect(throws: StorageError.self) { try VMStorage(directory: directory) }
    storage = nil
    let reopened = try VMStorage(directory: directory)
    try reopened.prepareDisk(size: 2048)
    let data = try Data(contentsOf: disk)
    #expect(data.count == 1024 * 1024)
    #expect(data.starts(with: Data("persistent guest data".utf8)))
}

@Test func rejectsEmptyDiskWithoutReplacingIt() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = try VMStorage(directory: directory)
    try Data().write(to: storage.disk)
    #expect(throws: StorageError.self) { try storage.prepareDisk() }
    #expect(try Data(contentsOf: storage.disk).isEmpty)
}

@Test func rejectsSymbolicLinkDisk() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = try VMStorage(directory: directory)
    let target = directory.appendingPathComponent("other-disk")
    try Data("do not change".utf8).write(to: target)
    try FileManager.default.createSymbolicLink(at: storage.disk, withDestinationURL: target)
    #expect(throws: StorageError.self) { try storage.prepareDisk() }
    #expect(try String(contentsOf: target, encoding: .utf8) == "do not change")
}
