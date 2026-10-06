# DanmakuOverlay

English | [简体中文](README.zh-CN.md)

![macOS 26+](https://img.shields.io/badge/macOS-26%2B-blue) ![Swift 6](https://img.shields.io/badge/Swift-6-orange) [![License: GPL-3.0-only](https://img.shields.io/badge/license-GPL--3.0--only-green)](LICENSE)

Danmaku (bullet comments) on top of any video player on macOS.

DanmakuOverlay draws a transparent, always-on-top, click-through danmaku layer over the window of the player you already use — IINA, mpv, Infuse, VLC, Safari, Chrome and more. It is not a player: it follows the player window, stays in sync with playback and renders the danmaku.

## Features

- **Works with your player** — follows the window as it moves, resizes, goes full screen, switches Spaces or moves between displays. Only the video picture is covered, and parts hidden behind other windows are cut out.
- **Fully click-through** — clicks, drags and scrolling go straight to the player underneath.
- **Accurate sync** — picks the most precise sync method for each player and falls back automatically. Seeks, pauses and speed changes are followed immediately; small drift is smoothed out without visible jumps.
- **Complete danmaku rendering** — scrolling, top, bottom, reverse and mode 7 advanced danmaku; gradient colors, outlines and shadows; collision-free track layout.
- **Filtering and merging** — filter by type, pool, color or block level, or by keyword, regex and user; merge similar danmaku in the style of [pakku](https://github.com/xmcp/pakku.js), including homophone matching.
- **Local danmaku files** — Bilibili XML and protobuf segment files (`.so`, `.pb`). Files with the same name next to the video are loaded automatically, and the danmaku offset is remembered per video.
- **Lightweight** — animation runs in the Core Animation render server, so CPU usage stays very low even with many danmaku on screen.
- **Native** — Swift 6, SwiftUI, AppKit and Core Animation, with no third-party dependencies.

### Supported players

| Player | Sync method | Typical accuracy |
|---|---|---|
| IINA / mpv | mpv JSON IPC | ±5 ms |
| Infuse and other apps that publish Now Playing | System Now Playing | 10–45 ms |
| VLC | Apple Events | ≈ ±60 ms after calibration |
| Safari / Chromium-based browsers | Apple Events + JavaScript | Depends on browser latency |
| Any other player | Manual clock (control bar and shortcuts) | — |

## Requirements

- macOS 26 or later on Apple silicon
- Xcode 26 or later to build

## Installation

No prebuilt binaries are provided. Build from source in the repository root:

```sh
xcodebuild -project DanmakuOverlay.xcodeproj -scheme DanmakuOverlay \
  -configuration Release -derivedDataPath build build
open build/Build/Products/Release/DanmakuOverlay.app
```

Or open `DanmakuOverlay.xcodeproj` in Xcode and run the `DanmakuOverlay` scheme.

The app is ad-hoc signed with a placeholder bundle identifier by default. Because macOS ties the Accessibility permission to the code signature, you may need to grant it again after rebuilding. To keep it, sign with your own identity — see [Signing](docs/DEVELOPMENT.md#signing).

## Usage

1. Click the menu bar icon › **Open Danmaku…** and choose a danmaku file, or drop it onto the floating control bar.
2. Choose **Attach to Window** and pick the player window, or press ⌃⌥A to follow the frontmost player. The sync method is chosen automatically and can be changed from the menu.
3. If danmaku appear too early or too late, adjust the offset with the −/+ buttons or ⌃⌥[ / ⌃⌥].

### Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌃⌥D | Show / hide danmaku |
| ⌃⌥P | Play / pause |
| ⌃⌥← / ⌃⌥→ | Seek backward / forward |
| ⌃⌥[ / ⌃⌥] | Danmaku earlier / later |
| ⌃⌥H | Show / hide the floating control bar |
| ⌃⌥A | Follow the frontmost player |

### Player setup

- **IINA** (recommended): in IINA › Settings › Advanced › Additional mpv options, add `input-ipc-server=/tmp/danmakuoverlay-mpv.sock`.
  - Or quit IINA and choose **Configure IINA** in DanmakuOverlay's menu or settings. This adds the same option to IINA's preferences and turns on IINA's advanced settings; remove the option in IINA's settings to undo it.
  - Without it, DanmakuOverlay falls back to Now Playing.
- **mpv**: add the same line to `mpv.conf`.
- **Infuse**: no setup needed. If Now Playing is unavailable, use the manual clock: align the position once on the control bar, after which Space and ←/→ pressed in Infuse are mirrored (requires Accessibility permission).
- **VLC**: allow DanmakuOverlay to control VLC when asked.
- **Safari / Chrome**: allow DanmakuOverlay to control the browser when asked, and enable “Allow JavaScript from Apple Events” in the browser (Safari: Settings › Advanced › Show features for web developers, then Develop › Allow JavaScript from Apple Events).

### Permissions

| Permission | Used for | Without it |
|---|---|---|
| Accessibility | Smooth window following, reading window titles, mirroring keys | Windows are followed by polling instead |
| Automation (per app) | VLC and browser sync | That sync method is unavailable and another one is used |

Screen Recording permission is not required.

## Limitations

- Browser sync cannot read videos inside cross-origin iframes; Now Playing is used instead.
- With several IINA windows open, sync follows the most recently opened one.
- VLC does not report its playback speed, so 1× is assumed.
- The path animation of mode 7 danmaku is not supported.
- Now Playing sync and window following rely on private macOS APIs (`MediaRemote`, `_AXUIElementGetWindow`). The app therefore cannot be distributed through the Mac App Store, and future macOS releases may break these features.

## Contributing

Issues and pull requests are welcome. See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for the architecture, tests and code style.

## Acknowledgements

- [DanmakuPlayer](https://github.com/Poker-sang/DanmakuPlayer) — the danmaku layout, advanced danmaku and Bilibili format handling are ported from this project.
- [pakku.js](https://github.com/xmcp/pakku.js) — the similar-danmaku merging algorithm and pinyin table.

## Disclaimer

DanmakuOverlay is an independent project and is not affiliated with or endorsed by Bilibili, IINA, Infuse, VLC or any other product mentioned here; their names are trademarks of their respective owners. The app does not download or provide any danmaku content. You supply your own danmaku files, and their copyright belongs to their original authors.

## License

[GPL-3.0-only](LICENSE). See [NOTICE](NOTICE) for third-party attributions.
