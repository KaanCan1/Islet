import SwiftUI

/// The last few screenshots, ready to be dragged somewhere else.
///
/// The point of the tab is the drag: macOS already shows its own thumbnail in
/// the corner for a few seconds, but you cannot pull a file out of it once it
/// has gone. Here the screenshot stays put until it is used or pushed off the
/// end by newer ones.
struct ShelfPanel: View {
    @ObservedObject var shelf: ShelfStore

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            // Centred rather than packed to the left: with only a few tiles the
            // shelf otherwise looks like it is falling off the side of the panel.
            HStack(spacing: Layout.shelfGap) {
                ForEach(shelf.items) { item in
                    ShelfTile(item: item, shelf: shelf)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.top, 4)
        .padding(.bottom, 9)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Screenshots")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))

            Text("click to open · drag out")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.38))

            Spacer(minLength: 0)

            IconButton(symbol: "xmark", size: 9, tint: .white) {
                shelf.clear()
            }
            .help("Clear the shelf. The files stay where they are.")
        }
        .frame(height: 16)
    }
}

/// One screenshot. Dragging it hands the file itself to whatever is underneath,
/// so dropping on Finder moves a real file and dropping in a chat attaches it.
private struct ShelfTile: View {
    let item: ShelfStore.Item
    @ObservedObject var shelf: ShelfStore

    @State private var hovering = false

    private var size: CGSize { Layout.shelfTile }

    var body: some View {
        thumbnail
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.white.opacity(hovering ? 0.35 : 0.14), lineWidth: 0.8)
            )
            .overlay(alignment: .topTrailing) { removeButton }
            .scaleEffect(hovering ? 1.04 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
            .onHover { hovering = $0 }
            .help(item.name)
            // The same thing the system thumbnail does when you click it: hand
            // the file to whatever opens screenshots, which is Preview and its
            // markup tools unless you have changed it.
            .onTapGesture { shelf.open(item) }
            .onDrag {
                let provider = NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
                provider.suggestedName = item.name
                return provider
            } preview: {
                dragPreview
            }
            .contextMenu {
                Button("Open") { shelf.open(item) }
                Button("Reveal in Finder") { shelf.revealInFinder(item) }
                Button("Copy") { shelf.copyToPasteboard(item) }
                Divider()
                Button("Remove from Shelf") { shelf.remove(item) }
            }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = item.thumbnail {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            // Quick Look is still working; a placeholder beats the tile popping in.
            LinearGradient(
                colors: [Color.white.opacity(0.20), Color.white.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            )
        }
    }

    /// Shown under the cursor while dragging. Without it macOS drags the whole
    /// tile including its hover ring, which looks like a piece of the panel came off.
    private var dragPreview: some View {
        Group {
            if let image = item.thumbnail {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Color.black.opacity(0.8)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    @ViewBuilder
    private var removeButton: some View {
        if hovering {
            Button {
                shelf.remove(item)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 14, height: 14)
                    .background(Circle().fill(.black.opacity(0.72)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.6))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(3)
            .transition(.opacity)
        }
    }
}
