import AppKit
import ImageIO
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Holds the last few screenshots so they can be dragged somewhere useful.
///
/// Nothing is copied: an item is a reference to the file `screencapture` already
/// wrote, and removing one from the shelf leaves it on disk. That also means the
/// shelf can go stale — files get moved and deleted behind its back — so it
/// prunes itself whenever the panel opens.
@MainActor
final class ShelfStore: ObservableObject {
    struct Item: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let addedAt: Date
        var thumbnail: NSImage?

        var name: String { url.lastPathComponent }

        static func == (lhs: Item, rhs: Item) -> Bool { lhs.id == rhs.id }
    }

    /// Newest first. Small on purpose: this is a landing strip, not an album.
    /// Four is what fits across the panel at the current tile size.
    static let capacity = 4

    @Published private(set) var items: [Item] = []

    var isEmpty: Bool { items.isEmpty }

    // MARK: - Mutation

    func add(_ url: URL) {
        guard !items.contains(where: { $0.url == url }) else { return }

        let item = Item(url: url, addedAt: Date(), thumbnail: nil)
        items.insert(item, at: 0)
        if items.count > Self.capacity { items.removeLast(items.count - Self.capacity) }

        loadThumbnail(for: item)
    }

    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
    }

    func clear() {
        items.removeAll()
    }

    /// Drops entries whose file is no longer where it was.
    func prune() {
        let manager = FileManager.default
        items.removeAll { !manager.fileExists(atPath: $0.url.path) }
    }

    // MARK: - Actions

    func open(_ item: Item) {
        NSWorkspace.shared.open(item.url)
    }

    func revealInFinder(_ item: Item) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func copyToPasteboard(_ item: Item) {
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects([item.url as NSURL])
    }

    // MARK: - Thumbnails

    /// Screenshots are images, and ImageIO turns one into a tile in a few
    /// milliseconds without waking the Quick Look daemon. Screen recordings land
    /// in the same folder with the same attribute, though, and a `.mov` has no
    /// bitmap to read — those go to Quick Look, which streams a rough frame
    /// first and refines it, so the tile is never empty for long.
    private func loadThumbnail(for item: Item) {
        if let image = Self.imageThumbnail(item.url) {
            apply(image, to: item)
            return
        }
        Self.quickLookThumbnail(item.url) { [weak self] image in
            self?.apply(image, to: item)
        }
    }

    private func apply(_ image: NSImage, to item: Item) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].thumbnail = image
    }

    private static var tileSize: CGSize {
        CGSize(width: Layout.shelfTile.width, height: Layout.shelfTile.height)
    }

    private static var pixelSize: CGFloat {
        max(tileSize.width, tileSize.height) * (NSScreen.main?.backingScaleFactor ?? 2)
    }

    private static func imageThumbnail(_ url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source),
              UTType(type as String)?.conforms(to: .image) == true else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return NSImage(cgImage: cgImage, size: tileSize)
    }

    private static func quickLookThumbnail(_ url: URL, update: @escaping (NSImage) -> Void) {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: tileSize,
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .all
        )
        // Fires more than once: a cheap representation, then better ones.
        QLThumbnailGenerator.shared.generateRepresentations(for: request) { representation, _, _ in
            guard let representation else { return }
            let image = NSImage(cgImage: representation.cgImage, size: tileSize)
            Task { @MainActor in update(image) }
        }
    }
}
