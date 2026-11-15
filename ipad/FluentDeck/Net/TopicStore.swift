import Foundation
import Observation

/// Latest state for one host topic. Each topic is observed separately, so a volume change
/// only re-renders the views that read "audio".
@Observable
final class TopicBox {
    private(set) var value: JSON?
    private(set) var version = 0
    /// When this state arrived on the iPad — used to interpolate positions without trusting the PC's clock.
    private(set) var receivedAt = Date.distantPast

    @ObservationIgnored private var cache: [ObjectIdentifier: (version: Int, value: Any?)] = [:]

    func set(_ newValue: JSON) {
        receivedAt = Date()
        guard newValue != value else { return }
        value = newValue
        version += 1
    }

    func clear() {
        value = nil
        version += 1
    }

    /// Decoded, cached per type until the next update.
    func decoded<T: Decodable>(_ type: T.Type) -> T? {
        let currentVersion = version // registers the observation dependency
        guard let value else { return nil }
        let key = ObjectIdentifier(type)
        if let hit = cache[key], hit.version == currentVersion { return hit.value as? T }
        let result = try? value.decode(type)
        cache[key] = (currentVersion, result)
        return result
    }
}

@MainActor
final class TopicStore {
    private var boxes: [String: TopicBox] = [:]

    func box(_ topic: String) -> TopicBox {
        if let b = boxes[topic] { return b }
        let b = TopicBox()
        boxes[topic] = b
        return b
    }

    func clearAll() {
        boxes.values.forEach { $0.clear() }
    }
}
