# FluentDeck

**FluentDeck is a touch controller for your Windows PC that runs on your iPad.** Think of it as Windows 11 crossed with a Stream Deck.

- **On the iPad:** a native SwiftUI app in iOS dark mode. Boards live in the system tab bar, with a standard toolbar for adding widgets, customizing and the PC's connection. Each board is laid out like Control Center: translucent modules on a dark ground tinted by whatever is playing (or a colour you choose), with deck keys that are modules of their own and thick pill sliders for volume. Menus, sheets and switches are the system's own.
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
| **Now Playing** | M ▴ / L / Tall / Wide | Album art, title, artist and album (centred in the large and tall sizes), a scrubber, shuffle/repeat, and a picker when several apps are playing. It reads Windows' media transport controls (the same source as the Quick Settings media flyout), so it works with Spotify, Apple Music, browsers, VLC and others without per-app code. |
| **Volume Mixer** | S ▴ / M ▴ / L / Banner / Wide | Output and mic volume at a glance; its drawer has a slider for each app with its real Windows icon. The output device's name opens the device switcher. |
| **Deck** | S / M / L / Wide / XL | Stream Deck–style keys, each a module on the board's own grid (twelve keys in an XL deck sit one per cell). They can launch apps and URIs, send hotkeys, type text, switch virtual desktops, call any host action, or run multi-step sequences. Keys can light up from live state (for example, when the mic is muted). Edit them on the iPad or in `deck.json`. |
| **System** | S ▴ / M ▴ / L | CPU ring, memory, battery and uptime, plus Lock / Sleep / Screen off. Its drawer adds disks and the busiest apps, measured only while it is open. |
| **Calendar** | S ▴ / M ▴ / L ▴ | What's next on the calendars set up on the iPad. Its drawer shows the week ahead. Works without the PC. |
| **Reminders** | S ▴ / M ▴ / L ▴ | Open reminders from the iPad, with a tap to tick one off. Its drawer has the full list. Works without the PC. |
| **Clock** | S / M / L | Large, light numerals, 12- or 24-hour. Runs on the iPad only. It's also the smallest example panel. |
| **Timer** | S / M / L | A countdown with quick lengths and a Pomodoro mode (25 minutes of focus, then a 5-minute break). Chimes when time's up. Runs on the iPad. |
| **Weather** | S / M / L / Wide | Conditions now, today's high and low, and the days ahead, for a place you search for or where the iPad is. Forecasts from [Open-Meteo](https://open-meteo.com) (free, no account); the place is sent to it. Runs on the iPad. |
| **Network & Disks** | S / M / L / Wide | The PC's download and upload speed with the last minute as a graph, and free space on its disks. |
| **Clipboard** | S / M / L | Send text copied on the iPad to the PC, paste it straight into the app in front, or copy the PC's clipboard to the iPad. iOS asks "Allow Paste" when the iPad's clipboard is read, unless you allow it in Settings › FluentDeck. |
| **Desktops** | S / M / Banner | Windows' virtual desktops by name, the one on screen lit; tap one to go there. Works even when a full-screen remote desktop (Omnissa Horizon, RDP) has the keyboard. |

**▴ Drawers.** Sizes marked ▴ are compact: they show the essentials and carry a small handle. Tap it or flick it up and a card slides up from the bottom of the screen with the rest of the widget's controls. Drag it down, tap outside or tap ✕ to put it away.

Calendar and Reminders read the iPad's own accounts through EventKit, so iOS asks for access the first time each is shown.

You can set up any number of **boards**; each is a tab in the tab bar (like Stream Deck profiles). A board fills the screen: 6 × 4 cells in landscape, 4 × 6 in portrait (4 × 7 if you add a seventh row), and it scrolls only if you add more than that. The toolbar holds **Add widgets** (+), **Customize** (pencil) and a **⋯** menu for renaming, reordering, adding and deleting boards, and **Settings**. The PC's name on the left opens its connection menu, where you can rename it, switch PCs or forget it.

**Boards that follow the PC.** In a board's **⋯ → Show for Apps…**, pick apps from those open on the PC. When one of them comes to the front, the iPad shows that board; leave the app and it goes back to the board you were on. Choosing a tab yourself stays put. Turn it off in Settings › Boards. While customizing, modules jiggle as on the Home Screen: tap **−** to remove one, **⋯** for its size and options (e.g. which deck page to show), or drag to reorder.

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
- The tray menu also has **Start with Windows**, **Allow editing keys from the iPad**, **Edit deck buttons (deck.json)** and **Paired devices** (where you can revoke access).
- Data lives in `%LOCALAPPDATA%\FluentDeck`: `deck.json`, `host.json` (port, display name, `allowDeckEditing`), `devices.json` (token hashes), `icons\` (key images sent from the iPad), and `host.log`.

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
| `-FluentDeckBoard N` | open board N (0-based) |
| `-FluentDeckDemoPlanner YES` | stand-in calendar events and reminders; iOS isn't asked for access |

## Settings

**⋯ → Settings…** holds:

- **This PC**: the name this iPad uses for the PC (the PC keeps its own), its address, and Switch PC.
- **Background**: the colours of whatever is playing, or one colour from swatches or a colour picker.
- **Accent color**: swatches of the iOS system colours or any colour; buttons, switches, gauges and the selected tab follow it.
- **Deck**: show or hide key names, light keys white or in the accent colour, haptic feedback on key presses.
- **Clock**: automatic, 12-hour or 24-hour.
- **Boards**: switch boards with the app in front on the PC.
- **Keep screen awake** while connected.

## Editing the deck

### On the iPad

1. On the PC, turn on **Allow editing keys from the iPad** in the FluentDeck tray menu. It is off by default because a key can launch any program.
2. On the iPad, tap the pencil (**Customize**), then tap a key. To add one, open the deck's **⋯** menu and choose **Add key…**.

For each key you set:

- **Label**: the name under the key.
- **When pressed**: open an app (picked from the PC's Start menu shortcuts, or a path or command you type), send a hotkey (modifier toggles plus a key, or several steps), open a link or app URI, type text, use a built-in PC control such as play/pause, mute, lock or sleep, or switch to a virtual desktop (by name, or next/previous), or switch to an app: bring an app that's open on the PC to the front, on whichever desktop it's on, and start it if it isn't running. A switch-to-app key lights up while its app is in front.
- **Icon**: an SF Symbol, the app's own Windows icon, or a photo from the iPad that fills the key.
- **Always lit**: keep the key lit (white, or the accent colour if Settings says so).

A desktop key lights up while its desktop is showing. Windows has no public way to switch desktops, so the PC presses Ctrl+Win+Left/Right as many times as needed, after bringing the taskbar to the front so a full-screen remote desktop client doesn't take the keys.

The editor also moves and deletes keys. The **⋯** menu adds, renames and deletes pages. Multi-step keys keep their steps and can only be re-labelled and re-iconed here; change their steps in `deck.json`. Store apps have no Start menu shortcut file, so they are not in the app list: use a **Link** such as `spotify:` or type a command such as `wt.exe`.

### In deck.json

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
`symbol` takes any SF Symbol name. `icon` takes any .exe/.lnk path and shows that program's real Windows icon, or a .png/.jpg image that fills the key (photos chosen on the iPad are saved under `icons\` in the data folder). Edits made on the iPad rewrite this file, so comments you add to it are replaced by a short header.

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
                HStack { Text(job.title); LevelBar(value: job.progress)
                         Button("Stop") { ctx.run("agents", "stop", ["id": .string(job.id)]) }
                            .buttonStyle(PillButtonStyle()) }
            }
        }
    }
}
// PanelCatalog.all: add AgentsPanel.spec
```

To give a widget a drawer, add `drawer: { AnyView(AgentsDrawer(ctx: $0)) }` to its spec (and `drawerSizes:` if only its compact sizes need one). A widget that needs no PC, like Calendar, leaves out `requires:` and reads its data on the iPad.

If a PC doesn't provide a topic yet, the picker shows that widget as unavailable, so older hosts degrade gracefully.

Shared pieces live in `ipad/FluentDeck/Design/`: `PillButtonStyle`, `IconButton`, `PillSlider` / `RemoteSlider` (optimistic and throttled), `LevelBar`, `Spinner`, `RingGauge`, `Banner`, `StatusDot`, `TextBox`, `SegmentedBar`, `ActionMenu` (a system menu from a list of `ActionItem`s), `DialogSheet`, and the `Theme` tokens.

## Design notes

- **Look:** iOS dark mode. The board is a Control Center-style grid: each widget sits on a translucent platter with large continuous corners, 14 pt apart, over a dark ground washed with the colours of the current cover art. Deck keys are modules too, laid on the same 14 pt rhythm, and light up white while on (as Control Center's toggles do), or in the accent colour if chosen; sliders are capsules that fill from the left, with no thumb. Colours are the iOS dark system palette, mapped in `Design/Theme.swift`.
- **System components:** boards are a `TabView`, so the tab bar is whatever the iPad's OS draws (floating at the top on iPadOS 18 and later, at the bottom before). The toolbar, menus, sheets, segmented controls, switches and activity indicators are the system's too. Dialogs follow the iOS sheet layout: Cancel on the left, the main action on the right. Drawers are the one custom presentation: iPadOS centres its own sheets, so a drawer is a card that rises from the bottom edge, as tall as its content.
- **Sizing for touch:** every control is at least 44 pt, sliders swell while you hold them, and deck keys respond to presses with scale and haptics.
- **Grid:** `DashboardGrid` is a custom `Layout` that packs 1×1 to 4×3 tiles first-fit. `DashboardGrid.fit` sizes the cells so 6 × 4 of them fill the screen exactly in landscape, and 4 × 6 in portrait (4 × 7 once a board has a seventh row).

## Security model

- The PC only accepts paired devices. Pairing uses a 6-digit code shown on the PC that expires after 3 minutes and allows 5 attempts. Paired iPads hold a 256-bit token in their Keychain, and the PC stores only its SHA-256 hash. You can revoke a device from the tray.
- **By default the iPad can't run arbitrary commands.** It can press deck buttons and call named panel actions; what a button does is defined only in `deck.json` on the PC. If you turn on **Allow editing keys from the iPad**, paired devices can change `deck.json`, which means they can make the PC launch any program. Leave it off unless you trust every paired device.
- Traffic is plain `ws://` on your LAN, which is fine for a home network. Don't expose port 47610 to the internet.

## Status and verification

- **Host core and DevHost:** built and tested end to end with `tools/smoke_test.py`. That covers pairing, auth rejection, snapshots, invokes, errors, coalescing, asset auth, deck hot-reload and broken-JSON recovery, and reconnecting with a token.
- **Windows host:** written against the real APIs (WinRT SMTC/UISettings, NAudio 2.2.1 Core Audio, Win32 SendInput/DNS-SD) and compile-checked against those signatures. It hasn't run on a PC yet, so do the first run with `--console` and check `host.log`.
- **iPad app:** built by CI on every push and driven through its screens on an iPad simulator against the DevHost (`FluentDeckUITests`). It hasn't run on a physical iPad yet, so Bonjour discovery and the Local Network prompt are unverified.

Known limits: Windows won't let a non-elevated app send keystrokes to an elevated (admin) window. Switching the default audio device uses the undocumented `IPolicyConfig` interface, the same one EarTrumpet and SoundSwitch use.
