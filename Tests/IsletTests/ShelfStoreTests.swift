import AppKit
import Foundation
import Testing
@testable import Islet

/// The shelf keeps references, never copies, and has to still hold them after
/// a restart. Each test gets its own defaults suite and its own folder of
/// screenshots, so the app's real shelf is never touched.
@MainActor
@Suite struct ShelfStoreTests {
    private let folder: URL
    private let suite: String
    private let defaults: UserDefaults

    init() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("islet-shelf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        suite = "islet-tests-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
    }

    /// A one-pixel PNG, so the thumbnail takes the ImageIO path a real
    /// screenshot does.
    private func screenshot(_ name: String) throws -> URL {
        let url = folder.appendingPathComponent("\(name).png")
        let image = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
                                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                  isPlanar: false, colorSpaceName: .deviceRGB,
                                                  bytesPerRow: 0, bitsPerPixel: 0))
        try #require(image.representation(using: .png, properties: [:])).write(to: url)
        return url
    }

    private func names(_ shelf: ShelfStore) -> [String] {
        shelf.items.map { $0.url.deletingPathExtension().lastPathComponent }
    }

    private func cleanUp() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: folder)
    }

    @Test func newestComesFirst() throws {
        defer { cleanUp() }
        let shelf = ShelfStore(defaults: defaults)
        shelf.add(try screenshot("a"))
        shelf.add(try screenshot("b"))
        #expect(names(shelf) == ["b", "a"])
    }

    @Test func theSameFileIsShelvedOnce() throws {
        defer { cleanUp() }
        let shelf = ShelfStore(defaults: defaults)
        let a = try screenshot("a")
        shelf.add(a)
        shelf.add(try screenshot("b"))
        shelf.add(a)
        #expect(names(shelf) == ["b", "a"])
    }

    @Test func holdsFourAndLetsTheOldestGo() throws {
        defer { cleanUp() }
        let shelf = ShelfStore(defaults: defaults)
        for name in ["a", "b", "c", "d", "e"] { shelf.add(try screenshot(name)) }
        #expect(ShelfStore.capacity == 4)
        #expect(names(shelf) == ["e", "d", "c", "b"])
        // Leaving the shelf is not leaving the disk.
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("a.png").path))
    }

    @Test func survivesARestartInOrder() throws {
        defer { cleanUp() }
        let shelf = ShelfStore(defaults: defaults)
        for name in ["a", "b", "c"] { shelf.add(try screenshot(name)) }

        #expect(names(ShelfStore(defaults: defaults)) == ["c", "b", "a"])
    }

    @Test func aFileMovedWhileClosedIsDroppedOnRestart() throws {
        defer { cleanUp() }
        let shelf = ShelfStore(defaults: defaults)
        for name in ["a", "b", "c"] { shelf.add(try screenshot(name)) }
        try FileManager.default.removeItem(at: folder.appendingPathComponent("b.png"))

        #expect(names(ShelfStore(defaults: defaults)) == ["c", "a"])
        // And the stored list is put right, not just the one in memory.
        #expect(defaults.stringArray(forKey: "shelfItems")?.count == 2)
    }

    @Test func pruneDropsWhatIsNoLongerThere() throws {
        defer { cleanUp() }
        let shelf = ShelfStore(defaults: defaults)
        for name in ["a", "b"] { shelf.add(try screenshot(name)) }
        try FileManager.default.removeItem(at: folder.appendingPathComponent("a.png"))

        shelf.prune()
        #expect(names(shelf) == ["b"])
        #expect(names(ShelfStore(defaults: defaults)) == ["b"])
    }

    @Test func removingAnItemLeavesTheFile() throws {
        defer { cleanUp() }
        let shelf = ShelfStore(defaults: defaults)
        shelf.add(try screenshot("a"))
        shelf.add(try screenshot("b"))

        shelf.remove(try #require(shelf.items.last))
        #expect(names(shelf) == ["b"])
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("a.png").path))
        #expect(names(ShelfStore(defaults: defaults)) == ["b"])
    }

    @Test func clearingIsRemembered() throws {
        defer { cleanUp() }
        let shelf = ShelfStore(defaults: defaults)
        shelf.add(try screenshot("a"))
        shelf.clear()

        #expect(shelf.isEmpty)
        #expect(ShelfStore(defaults: defaults).isEmpty)
    }
}
