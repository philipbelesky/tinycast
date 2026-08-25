import SwiftUI

/// Row icon decoding off the main thread; warm icons seed synchronously, so no flash.
struct AppIconView: View {
    let app: AppEntry
    /// What to draw: `iconSource` unless the caller passes the launcher list's category answer.
    private let source: EntryIcon
    @State private var image: NSImage?

    init(app: AppEntry, source: EntryIcon? = nil) {
        self.app = app
        self.source = source ?? app.iconSource
        // Cache-only, so a warm icon paints on the same frame.
        _image = State(initialValue: IconCache.cached(self.source, fileURL: app.url))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable()
            } else {
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(Theme.Colors.iconPlaceholder)
            }
        }
        // Keyed on the icon, not the entry: re-skinning an extension leaves `id` untouched.
        .task(id: IconRequest("\(app.id)|\(source)")) {
            if let warm = IconCache.cached(source, fileURL: app.url) {
                image = warm
                return
            }
            image = await IconCache.loadAsync(source, fileURL: app.url)
        }
    }
}
