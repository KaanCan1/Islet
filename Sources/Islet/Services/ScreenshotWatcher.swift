import Foundation

/// Notices new screenshots the moment macOS writes them to disk.
///
/// The folder comes from `com.apple.screencapture`, which is usually the Desktop
/// — somewhere full of files Islet has no business picking up. So a new file only
/// counts if `screencapture` stamped it with the `kMDItemIsScreenCapture`
/// extended attribute. That is written as the file is saved, which is why the
/// attribute is read directly rather than through Spotlight: the metadata index
/// carries the same flag but arrives whenever it feels like it.
final class ScreenshotWatcher {
    /// Called on the main queue with a file that has just been captured.
    var onCapture: ((URL) -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var directory: URL?
    private var seen: Set<String> = []
    private let queue = DispatchQueue(label: "dev.kaancankurt.islet.screenshots")

    private static let attribute = "com.apple.metadata:kMDItemIsScreenCapture"

    var isRunning: Bool { source != nil }

    // MARK: - Lifecycle

    func start() {
        queue.async { [weak self] in self?.arm() }
    }

    func stop() {
        queue.async { [weak self] in self?.disarm() }
    }

    private func arm() {
        disarm()

        let folder = Self.screenshotDirectory()
        directory = folder

        // Everything already there predates Islet and stays where it is.
        seen = Set(Self.names(in: folder))

        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("Islet: cannot watch \(folder.path) for screenshots")
            return
        }
        descriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let event = source.data
            // The folder itself went away (or was renamed): re-resolve it rather
            // than keep watching a descriptor that no longer points anywhere.
            if event.contains(.delete) || event.contains(.rename) {
                self.arm()
            } else {
                self.rescan()
            }
        }
        source.setCancelHandler { [descriptor] in
            if descriptor >= 0 { close(descriptor) }
        }
        source.resume()
        self.source = source
    }

    private func disarm() {
        source?.cancel()
        source = nil
        descriptor = -1
        seen = []
    }

    // MARK: - Detection

    private func rescan() {
        guard let directory else { return }
        let current = Self.names(in: directory)
        let fresh = current.filter { !seen.contains($0) }
        seen = Set(current)

        for name in fresh {
            confirm(directory.appendingPathComponent(name), attempt: 0)
        }
    }

    /// The directory event fires when the file is linked in, which can be a beat
    /// before `screencapture` finishes writing it and sets the attribute. So a
    /// new file gets a few chances to identify itself before it is dropped.
    private func confirm(_ url: URL, attempt: Int) {
        if Self.isScreenCapture(url) {
            DispatchQueue.main.async { [weak self] in self?.onCapture?(url) }
            return
        }
        let delays: [Double] = [0.15, 0.25, 0.4, 0.7]
        guard attempt < delays.count else { return }
        queue.asyncAfter(deadline: .now() + delays[attempt]) { [weak self] in
            guard let self, FileManager.default.fileExists(atPath: url.path) else { return }
            self.confirm(url, attempt: attempt + 1)
        }
    }

    private static func isScreenCapture(_ url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return getxattr(path, attribute, nil, 0, 0, XATTR_NOFOLLOW) >= 0
        }
    }

    private static func names(in folder: URL) -> [String] {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )
        return (contents ?? []).map(\.lastPathComponent)
    }

    /// Where the screenshot UI is currently set to save. Falls back to the
    /// Desktop, which is what macOS itself does when the key is missing.
    ///
    /// Testing hook, same spirit as `ISLET_DEMO`: `ISLET_SCREENSHOT_DIR` points
    /// the watcher somewhere harmless so the shelf can be exercised without
    /// dropping files on a real Desktop.
    static func screenshotDirectory() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let fallback = home.appendingPathComponent("Desktop")

        if let override = ProcessInfo.processInfo.environment["ISLET_SCREENSHOT_DIR"],
           !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }

        guard let raw = UserDefaults(suiteName: "com.apple.screencapture")?
            .string(forKey: "location"), !raw.isEmpty else { return fallback }

        let expanded = (raw as NSString).expandingTildeInPath
        let url = expanded.hasPrefix("file:")
            ? URL(string: expanded) ?? fallback
            : URL(fileURLWithPath: expanded)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return fallback }
        return url
    }
}
