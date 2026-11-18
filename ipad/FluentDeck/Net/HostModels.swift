import Foundation

// Typed views of the built-in host topics (see docs/PROTOCOL.md). Decoding is lenient:
// a panel that can't decode its topic just shows its empty state.

struct HostEndpoint: Codable, Hashable, Identifiable {
    var host: String
    var port: Int
    var hostId: String?
    var name: String

    var id: String { hostId ?? "\(host):\(port)" }

    var webSocketURL: URL? {
        let h = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host // IPv6 literal
        return URL(string: "ws://\(h):\(port)/ws")
    }

    func assetURL(_ path: String) -> URL? {
        let h = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        return URL(string: "http://\(h):\(port)\(path)")
    }
}

struct PanelDescriptor: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var icon: String
    var version: Int
    var actions: [String]
}

struct MediaSource: Codable, Hashable, Identifiable {
    var appId: String
    var name: String
    var id: String { appId }
}

struct MediaState: Codable, Equatable {
    var hasSession: Bool
    var source: MediaSource?
    var title: String?
    var artist: String?
    var album: String?
    var artwork: String?
    var status: String
    var position: Double
    var duration: Double
    var positionAt: Double
    var canPlay: Bool
    var canPause: Bool
    var canNext: Bool
    var canPrevious: Bool
    var canSeek: Bool
    var canShuffle: Bool
    var canRepeat: Bool
    var shuffle: Bool?
    var `repeat`: String?
    var sessions: [MediaSource]

    var isPlaying: Bool { status == "playing" }
}

struct AudioEndpointState: Codable, Equatable {
    var id: String
    var name: String
    var volume: Double
    var muted: Bool
}

struct AudioDevice: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var isDefault: Bool
}

struct AudioAppState: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var icon: String?
    var volume: Double
    var muted: Bool
    var active: Bool
}

struct AudioState: Codable, Equatable {
    var output: AudioEndpointState?
    var input: AudioEndpointState?
    var devices: [AudioDevice]
    var sessions: [AudioAppState]
}

struct BatteryState: Codable, Equatable {
    var percent: Int
    var charging: Bool
}

/// Windows' virtual desktops. `current` and each `index` count from 1; `current` is 0 when the PC
/// can't tell.
struct DesktopsState: Codable, Equatable {
    struct Desktop: Codable, Equatable, Identifiable {
        var index: Int
        var name: String
        var id: Int { index }
    }
    var current: Int
    var desktops: [Desktop]
    /// Keys the PC presses to make a full-screen remote desktop let go of the keyboard.
    var releaseKeys: String?
}

/// An app with a window open on the PC. `exe` is the lower-case file name boards and keys match on.
struct RunningApp: Codable, Equatable, Identifiable, Hashable {
    var exe: String
    var name: String
    var path: String?
    var icon: String?
    var id: String { exe }
}

struct AppsState: Codable, Equatable {
    var foreground: RunningApp?
    var running: [RunningApp]
}

/// The PC's main connection in bytes per second, with the last minute of samples, and its disks.
struct NetworkState: Codable, Equatable {
    struct Disk: Codable, Equatable, Identifiable {
        var name: String
        var freeGb: Double
        var totalGb: Double
        var id: String { name }
    }
    var adapter: String?
    var address: String?
    var downBps: Double
    var upBps: Double
    var downHistory: [Double]
    var upHistory: [Double]
    var disks: [Disk]
}

struct SystemState: Codable, Equatable {
    var hostName: String
    var cpu: Double
    var memory: Double
    var memoryUsedGb: Double
    var memoryTotalGb: Double
    var battery: BatteryState?
    var uptimeSeconds: Double
}

/// Measured by the PC only when asked (the system panel's `details` action).
struct SystemDetailsState: Codable, Equatable {
    struct Disk: Codable, Equatable, Identifiable {
        var name: String
        var freeGb: Double
        var totalGb: Double
        var id: String { name }
    }

    struct BusyProcess: Codable, Equatable, Identifiable {
        var name: String
        /// Percent of the whole machine.
        var cpu: Double
        var memoryMb: Double
        var id: String { name }
    }

    var disks: [Disk]
    var processes: [BusyProcess]
}

struct DeckBinding: Codable, Equatable {
    var topic: String
    var path: String
    var equals: JSON?
}

struct DeckButtonModel: Codable, Equatable, Identifiable {
    var id: String
    var label: String
    var symbol: String?
    var symbolOn: String?
    var icon: String?
    /// The icon is a picture that fills the key, not a program's icon set on it.
    var iconFill: Bool?
    var style: String
    var state: DeckBinding?
    var kind: String
}

struct DeckPageModel: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var columns: Int?
    var buttons: [DeckButtonModel]
}

struct DeckState: Codable, Equatable {
    var pages: [DeckPageModel]
    var error: String?
    /// The PC lets paired devices edit keys (off by default; set from its tray menu).
    var editable: Bool?
}
