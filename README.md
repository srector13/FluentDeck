# FluentDeck

**FluentDeck is a touch controller for your Windows PC that runs on your iPad.** Think of it as Windows 11 crossed with a Stream Deck.

- **On the iPad:** a native SwiftUI app that follows Windows 11's Fluent design. It uses Mica surfaces, widget cards, SelectorBar tabs, MenuFlyouts, ContentDialogs, InfoBars, and WinUI-style sliders and toggles, all sized for touch. Its accent color and light/dark mode **follow your PC's live**.
- **On the PC:** a small tray app (native on Arm64, so it runs natively on your Snapdragon). It exposes media, audio, system stats and a configurable button deck over your LAN.

```
 iPad (SwiftUI)                                   Windows PC (.NET 10 tray app)
┌──────────────────────────┐   ws://pc:47610/ws  ┌──────────────────────────────────┐
│ Boards ▸ widget grid     │◀──── state ────────│ Hub ─ topics ─┬─ media  (SMTC)   │
│  Now Playing  Mixer      │───── invoke ──────▶│               ├─ audio  (CoreAudio)
│  Deck keys    System     │   GET /assets/…    │               ├─ system (Win32)  │
│  Clock  …your panels     │◀─ art & app icons ─│               ├─ theme  (accent) │
└──────────────────────────┘   Bonjour discovery └───────────────┴─ deck   (deck.json)
```

## What's in the box

| Widget | Sizes | What it does |
|---|---|---|
| **Now Playing** | M / L / Wide | Album art, title and artist, a scrubber, shuffle/repeat, and a picker when several apps are playing. It reads Windows' media transport controls (the same source as the Quick Settings media flyout), so it works with Spotify, Apple Music, browsers, VLC and others without per-app code. |
| **Volume Mixer** | S / M / L / Wide | Master volume, the mic, and a slider for each app with its real Windows icon. Includes an output-device switcher. |
| **Deck** | S / M / L / Wide | Stream Deck–style keys defined in `deck.json`. They can launch apps and URIs, send hotkeys, type text, call any host action, or run multi-step sequences. Keys can light up from live state (for example, when the mic is muted). |
| **System** | S / M / L | CPU ring, memory, battery and uptime, plus Lock / Sleep / Screen off. |
| **Clock** | S / M / L | Runs on the iPad only. It's also the smallest example panel. |

You can set up any number of **boards** (tabs, like Stream Deck profiles). On each widget, the **⋯** menu offers size, widget-specific options (e.g. which deck page to show) and *Unpin*. **Customize** lets you drag widgets to reorder them, and **Add widgets** opens a Windows-style picker with a live preview.

## Quick start

### 1. Run the host on the PC

You need the .NET 10 SDK to build it. The published exe is self-contained.

```powershell
cd host
dotnet publish FluentDeck.Host -c Release -r win-arm64 -p:PublishSingleFile=true -p:SelfContained=true -o publish
.\publish\FluentDeck.Host.exe          # add --console to watch logs live
```

- The first time it runs, the pairing window opens. Later, click the tray icon (or use **Pair new device…** in its menu).
- If Windows Firewall prompts you, allow **Private networks**. You can also use the tray menu: **Allow through Windows Firewall…**.
- The tray menu also has **Start with Windows**, **Edit deck buttons (deck.json)** and **Paired devices** (where you can revoke access).
- Data lives in `%LOCALAPPDATA%\FluentDeck`: `deck.json`, `host.json` (port, display name), `devices.json` (token hashes), and `host.log`.

### 2. Build the iPad app

You need Xcode 16+ (it's written against the iOS 18+ SDK and deploys to iPadOS 17+) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
cd ipad
xcodegen generate
open FluentDeck.xcodeproj      # set your Team and bundle id, then run on the iPad
```

The PC should show up under **PCs on this network** via Bonjour. Tap it and enter the 6-digit code. After that the iPad reconnects to that PC on its own, including after sleep or a network change. Allow **Local Network** access when iOS asks.

### 3. Developing without the PC: the DevHost

`host/FluentDeck.DevHost` is a cross-platform host with simulated media, audio and system panels and the real deck. Run it on your Mac (or anywhere with .NET 10), then point the Simulator at `127.0.0.1`. That gives your screenshot and Maestro pipeline a stable, deterministic backend.

```bash
FLUENTDECK_HOME=/tmp/fd FLUENTDECK_PAIR_CODE=123456 dotnet run --project host/FluentDeck.DevHost
python3 host/tools/smoke_test.py --code 123456 --deck-file /tmp/fd/deck.json   # protocol test (pip install websockets)
```

## Installing with Feather

**Build unsigned IPA** (`.github/workflows/build-ipa.yml`) is a manual workflow (Actions → Build unsigned IPA → Run workflow). It builds the app for Release with signing disabled and publishes a GitHub Release `v1.0.N` with:

- `FluentDeck-v1.0.N-unsigned.ipa`: open it in Feather on the iPad and re-sign it with your certificate.
- `FluentDeck-Host-v1.0.N-win-arm64.zip` / `-win-x64.zip`: the PC tray host as a single self-contained exe.

**CI** (`.github/workflows/ci.yml`) runs on every push. It runs the protocol smoke test against the DevHost, cross-compiles the Windows host, then starts the DevHost on a Mac runner and runs `FluentDeckUITests` on an iPad simulator against it. The screenshots are uploaded as the `fluentdeck-screenshots-N` artifact.

The UI tests drive the app with launch arguments (`ipad/FluentDeck/App/LaunchOptions.swift`):

| Argument | Effect |
|---|---|
| `-FluentDeckReset YES` | start with no saved PCs, tokens, layout or preferences |
| `-FluentDeckConnect host[:port]` | connect to this PC at launch |
| `-FluentDeckPairCode 123456` | answer the pairing prompt with this code |
| `-FluentDeckTheme light\|dark` | force light or dark |
| `-FluentDeckBoard N` | open board N (0-based) |

## Editing the deck

Open `deck.json` from the tray menu. **Save it and the iPad updates instantly.** If the JSON is invalid, the iPad keeps your last good buttons and shows an InfoBar with the parse error.

```jsonc
{ "id": "mic", "label": "Mic", "symbol": "mic", "symbolOn": "mic.slash",
  "state":  { "topic": "audio", "path": "input.muted", "equals": true },   // lights up while muted
  "action": { "type": "builtin", "panel": "audio", "action": "toggleMicMute" } }

{ "id": "code", "label": "VS Code", "icon": "%LOCALAPPDATA%\\Programs\\Microsoft VS Code\\Code.exe",
  "action": { "type": "launch", "target": "code", "hidden": true } }

{ "id": "standup", "label": "Stand-up", "symbol": "person.3",
  "action": { "type": "sequence", "steps": [
    { "type": "url", "target": "msteams:" },
    { "type": "delay", "ms": 1500 },
    { "type": "keys", "keys": "Ctrl+Shift+M" } ] } }
```

Action types: `launch`, `url`, `keys` (`Win+Shift+S`; separate chords with spaces, as in `Ctrl+K Ctrl+S`), `text`, `builtin` (any host panel action), `sequence`, `delay`.
`symbol` takes any SF Symbol name. `icon` takes any .exe/.lnk path and shows that program's real Windows icon.

## Adding a widget panel

Each widget is two small pieces that plug into registries. Everything else comes for free: sizing, the ⋯ menu, persistence, boards, reordering, theming and the picker.

**PC side: a `PanelProvider`** (state in, actions out):

```csharp
internal sealed class AgentsPanel : PanelProvider
{
    public override PanelDescriptor Descriptor { get; } = new("agents", "Agents", "sparkles", 1, ["stop"]);

    public override Task StartAsync(CancellationToken ct)
    {
        // poll or subscribe to something, then:
        Publish(new { running = 2, jobs = new[] { new { id = "a1", title = "Refactor auth", progress = 0.4 } } });
        return Task.CompletedTask;
    }

    public override Task<object?> InvokeAsync(string action, JsonObject args, CancellationToken ct) => action switch
    {
        "stop" => StopJob(args.String("id")),
        _ => throw UnknownAction(action),
    };
}
// Program.cs:  builder.Services.AddPanel<AgentsPanel>();
```

`Publish` drops duplicate states and the hub caps updates at ~30/s per topic, so it's fine to publish from a tight poll. Deck buttons can call the new actions right away with `{ "type": "builtin", "panel": "agents", "action": "stop" }`.

**iPad side: a view and a spec:**

```swift
struct AgentsPanel: View {
    let ctx: PanelContext
    static let spec = PanelSpec(kind: "agents", title: "Agents", summary: "Running agent jobs.",
                                symbol: "sparkles", requires: "agents",
                                sizes: [.medium, .large], defaultSize: .large,
                                view: { AnyView(AgentsPanel(ctx: $0)) })

    struct State: Decodable { var running: Int; var jobs: [Job] }
    struct Job: Decodable, Identifiable { var id: String; var title: String; var progress: Double }

    var body: some View {
        if let s = ctx.state("agents", as: State.self) {
            ForEach(s.jobs) { job in
                HStack { Text(job.title); FluentProgressBar(value: job.progress)
                         Button("Stop") { ctx.run("agents", "stop", ["id": .string(job.id)]) }
                            .buttonStyle(FluentButtonStyle()) }
            }
        }
    }
}
// PanelCatalog.all: add AgentsPanel.spec
```

If a PC doesn't provide a topic yet, the picker shows that widget as unavailable, so older hosts degrade gracefully.

Reusable Fluent components live in `ipad/FluentDeck/Fluent/`: `FluentButtonStyle`, `FluentIconButton`, `FluentSlider` / `RemoteSlider` (optimistic and throttled), `FluentToggleStyle`, `FluentProgressBar`, `FluentProgressRing`, `FluentRingGauge`, `InfoBar`, `InfoBadge`, `FluentTextBox`, `SelectorBar`, `FlyoutButton` and `MenuFlyoutView`, `ContentDialog` and `DialogButton`, `SettingsCard`, `MicaBackground`, and the `FluentTheme` tokens.

## Design notes

- **Tokens** are WinUI 3's theme resources (for example `TextFillColorSecondary` and `ControlFillColorDefault`), in both dark and light. They're mapped in `FluentTheme.swift`, and the accent ramp comes from the PC's `UISettings`.
- **Sizing for touch:** the type ramp is scaled about 1.15×, every control is at least 44 pt, slider thumbs grow while you hold them, and deck keys respond to presses with scale and haptics.
- **Fonts and icons:** Segoe UI Variable and Segoe Fluent Icons aren't licensed for iOS, so the app uses SF Pro on the same type ramp and SF Symbols at regular weight. These read very close to Fluent. Icons go through plain symbol-name strings, so swapping in Microsoft's MIT-licensed Fluent UI System Icons later is a contained change.
- **Grid:** `DashboardGrid` is a custom `Layout` that packs 1×1 to 4×2 tiles first-fit. On an 11" iPad that's 6 columns in landscape and 4 in portrait.

## Security model

- The PC only accepts paired devices. Pairing uses a 6-digit code shown on the PC that expires after 3 minutes and allows 5 attempts. Paired iPads hold a 256-bit token in their Keychain, and the PC stores only its SHA-256 hash. You can revoke a device from the tray.
- **The iPad can't run arbitrary commands.** It can press deck buttons and call named panel actions; what a button does is defined only in `deck.json` on the PC.
- Traffic is plain `ws://` on your LAN, which is fine for a home network. Don't expose port 47610 to the internet.

## Status and verification

- **Host core and DevHost:** built and tested end to end with `tools/smoke_test.py`. That covers pairing, auth rejection, snapshots, invokes, errors, coalescing, asset auth, deck hot-reload and broken-JSON recovery, and reconnecting with a token.
- **Windows host:** written against the real APIs (WinRT SMTC/UISettings, NAudio 2.2.1 Core Audio, Win32 SendInput/DNS-SD) and compile-checked against those signatures. It hasn't run on a PC yet, so do the first run with `--console` and check `host.log`.
- **iPad app:** syntax-checked, and its models were checked field by field against live host JSON. It hasn't been compiled in Xcode yet, so expect a quick fix-up pass on the first build.

Known limits: Windows won't let a non-elevated app send keystrokes to an elevated (admin) window. Switching the default audio device uses the undocumented `IPolicyConfig` interface, the same one EarTrumpet and SoundSwitch use.
