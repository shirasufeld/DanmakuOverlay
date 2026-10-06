# Development

## Building and testing

Requires Xcode 26 or later. If you use a non-default Xcode, select it first with `export DEVELOPER_DIR=/path/to/Xcode.app`.

```sh
swift test --package-path DanmakuKit                # core logic tests
xcodebuild -project DanmakuOverlay.xcodeproj -scheme DanmakuOverlay \
  -destination 'platform=macOS,arch=arm64' build test
xcrun swift-format lint -r DanmakuOverlay DanmakuKit/Sources DanmakuKit/Tests
```

Please make sure all three pass before opening a pull request. Code style is defined in `.swift-format`.

### Signing

Build settings for the app live in `Config/App.xcconfig`. By default the app is ad-hoc signed with the placeholder bundle identifier `com.example.DanmakuOverlay`.

macOS ties the Accessibility permission to the code signature, so with ad-hoc signing it may have to be granted again after each rebuild. To avoid that, create `Config/Local.xcconfig` (git-ignored) with your own stable identity:

```
PRODUCT_BUNDLE_IDENTIFIER = com.yourname.DanmakuOverlay
CODE_SIGN_IDENTITY = Apple Development
DEVELOPMENT_TEAM = YOURTEAMID
```

## Project layout

- **`DanmakuKit/DanmakuCore`** — pure logic, nonisolated and `Sendable`, testable without the app: models, parsers, filtering and merging, layout, the clock model, VLC phase estimation and the settings model.
- **`DanmakuKit/DanmakuText`** — Core Text measurement and rasterization. Both share the same metrics, so collision checks match the drawn size exactly.
- **`DanmakuOverlay`** — the app (MainActor by default):
  - `Overlay/` — the click-through panel
  - `Tracking/` — window following
  - `Render/` — Core Animation rendering
  - `Sync/` — playback sync adapters, plus JXA helper scripts bundled in the app and run by `osascript`
  - `Library/` — the danmaku pipeline and library
  - `Settings/`, `UI/`, `System/`
- **`Tools/`** — `gen-pinyin.swift` regenerates `pinyin.bin` from DanmakuPlayer's C# pinyin dictionary; `make-sync-fixture.swift` creates the sync test video (see below).

## Architecture

```
PlaybackSource (actor: mpv / NowPlaying / VLC / Browser / Manual)
   └─ AsyncStream<SourceEvent> ─▶ PlaybackClock (ClockModel: keep / slew / jump)
                                       └─ Anchor(hostTime, mediaTime, rate)
LocalFileSource ─▶ FilterChain (Kind ▸ Blocklist ▸ Combiner) ─▶ LayoutEngine ─▶ PlacedTimeline
                                                                    └─▶ DanmakuRenderer
                                                                          TimelineLayer (CA local time = video time)
WindowTracker (AXObserver + CGWindowList + display link) ─▶ ContentRectResolver ─▶ OverlayPanel (click-through)
SettingsStore (JSON) ─▶ SettingsImpact: render / restyle / relayout / refilter, recomputing only what is needed
```

### Playback sync

Each `PlaybackSource` pushes `PlaybackState` values stamped with a `hostTime`. `PlaybackClock` keeps an anchor `(hostTime, mediaTime, rate)`: small drift is slewed away at up to ±5 % speed, while seeks, pauses and rate changes re-anchor immediately.

| Source | Mechanism |
|---|---|
| mpv / IINA | mpv JSON IPC over `input-ipc-server` |
| Now Playing | Private `MediaRemote` framework, queried from a JXA helper run by `/usr/bin/osascript` because MediaRemote only answers Apple-signed processes |
| VLC | Whole-second position via Apple Events, refined by estimating where the second boundaries fall |
| Browsers | Apple Events running JavaScript that reads the page's `<video>` element |
| Manual | Clock driven by the control bar and shortcuts, optionally mirroring the player's Space and ←/→ keys |

### Rendering

The container layer's local time is mapped to `K + video time − offset` (`local = (host − beginTime) · speed + timeOffset`).

- Each danmaku is a `CALayer` with a `CGImage`, whose animation uses video time as its `beginTime`.
- Pausing, rate changes and drift correction only change three properties of the container layer; the render server advances every danmaku.
- The app adds and removes layers about four times a second, so main-thread stalls do not drop danmaku frames.
- Text images are kept in a byte-bounded LRU cache and rasterized ahead of time in the background.

### Window following

With Accessibility permission, AX notifications trigger per-frame following while the target window moves; otherwise the window list is polled at 10 Hz. The window ID is resolved with the private `_AXUIElementGetWindow`, looked up at run time so that its absence is not fatal.

### Extension points

- **New sync method**: implement `PlaybackSource`, then register it in `AdapterRegistry` and `PlayerCatalog`.
- **New danmaku source**: implement `DanmakuSource` and extend `SourceDescriptor`.

## Verifying sync accuracy

```sh
swift Tools/make-sync-fixture.swift Tools/fixtures 180   # requires ffmpeg
/Applications/IINA.app/Contents/MacOS/iina-cli \
  --mpv-input-ipc-server=/tmp/danmakuoverlay-mpv.sock Tools/fixtures/sync.mp4
```

This creates a video with a burnt-in timecode and a matching `sync.xml` (`Tools/fixtures/` is git-ignored).

- Attach to the IINA window; `sync.xml` is loaded automatically.
- The `▼ mm:ss` top danmaku shown every second should appear together with the on-screen timecode.
- Turn on “Show statistics in the menu” in settings to see the live drift in milliseconds.

## Porting notes

The core algorithms are ported from [DanmakuPlayer](https://github.com/Poker-sang/DanmakuPlayer) (WinUI 3).

- **Ported**: interval-based track allocation and analytic catch-up distance for scrolling danmaku (`Danmaku.Position.cs`), mode 7 parsing and easing, Bilibili XML / protobuf field layouts, and the pakku merging algorithm with its pinyin table.
- **Redesigned for macOS**:
  - Per-frame Win2D redraw → animation driven by the Core Animation render server
  - Embedded WebView2 playback → sync adapters for external players
  - Built-in progress bar → anchored clock that follows an external player, with drift smoothing
  - Linear scans → binary search
  - AutoSettingsPage → SwiftUI settings backed by forward-compatible JSON
- **Behavior differences**:
  - Timestamp and pool fields are read from the correct positions in new-format XML, and the dmid is kept for old-format XML.
  - Mode 2 and 3 danmaku are rendered instead of being dropped.
  - Pinyin distance compares pinyin rather than the original text.
  - A danmaku joins the cluster it matched rather than the newest cluster.
  - Danmaku excluded from merging are kept as is.
  - The protected attribute is read from bit 0 of `attr` (the original flags enum defines it as 0).
