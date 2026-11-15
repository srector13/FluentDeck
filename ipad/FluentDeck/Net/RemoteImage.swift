import SwiftUI
import UIKit

/// In-memory cache for host assets. Asset paths are content hashes, so entries never go stale.
@MainActor
final class AssetCache {
    static let shared = AssetCache()
    private let cache = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    init() { cache.countLimit = 300 }

    func cached(_ path: String) -> UIImage? { cache.object(forKey: path as NSString) }

    func load(_ path: String, from connection: HostConnection) async -> UIImage? {
        if let hit = cached(path) { return hit }
        if let running = inFlight[path] { return await running.value }
        guard let request = connection.assetRequest(path) else { return nil }
        let task = Task<UIImage?, Never> {
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = UIImage(data: data) else { return nil }
            return image
        }
        inFlight[path] = task
        let image = await task.value
        inFlight[path] = nil
        if let image { cache.setObject(image, forKey: path as NSString) }
        return image
    }
}

/// Shows an `/assets/…` image from the PC (album art, app icons), with a placeholder.
struct RemoteImage<Placeholder: View>: View {
    let path: String?
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder

    @Environment(HostConnection.self) private var connection
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                placeholder()
            }
        }
        .task(id: path) {
            guard let path else { image = nil; return }
            if let hit = AssetCache.shared.cached(path) { image = hit; return }
            let loaded = await AssetCache.shared.load(path, from: connection)
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }
}

extension RemoteImage where Placeholder == Color {
    init(path: String?, contentMode: ContentMode = .fill) {
        self.init(path: path, contentMode: contentMode) { Color.clear }
    }
}
