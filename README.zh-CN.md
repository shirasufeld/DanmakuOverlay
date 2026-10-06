# DanmakuOverlay

[English](README.md) | 简体中文

![macOS 26+](https://img.shields.io/badge/macOS-26%2B-blue) ![Swift 6](https://img.shields.io/badge/Swift-6-orange) [![License: GPL-3.0-only](https://img.shields.io/badge/license-GPL--3.0--only-green)](LICENSE)

在 macOS 的任意视频播放器上显示弹幕。

DanmakuOverlay 在你正在使用的播放器窗口（IINA、mpv、Infuse、VLC、Safari、Chrome 等）上方叠加一层透明、置顶、鼠标穿透的弹幕层。它不是播放器：它负责跟随播放器窗口、与播放进度同步并绘制弹幕。

## 功能

- **配合现有播放器** —— 随窗口移动、缩放、全屏、切换 Space、跨显示器。只覆盖视频画面，被其他窗口遮挡的部分会被挖空。
- **完全鼠标穿透** —— 点击、拖动、滚轮都直达下面的播放器。
- **精确同步** —— 为每个播放器自动选择最精确的同步方式，连不上时自动降级。跟随拖动进度、暂停和倍速变化，小幅漂移会被平滑修正，弹幕不会跳动。
- **完整的弹幕渲染** —— 滚动、顶部、底部、逆向及 M7 高级弹幕；渐变色、描边与阴影；防碰撞的轨道布局。
- **过滤与合并** —— 按类型、弹幕池、彩色、屏蔽等级过滤，支持关键词、正则和用户屏蔽；按 [pakku](https://github.com/xmcp/pakku.js) 的方式合并相似弹幕，支持拼音同音匹配。
- **本地弹幕文件** —— 支持 B 站 XML 和 protobuf 分段文件（`.so`、`.pb`）。视频同目录下的同名弹幕文件会自动加载，弹幕偏移按视频记住。
- **轻量** —— 弹幕动画由 Core Animation 渲染服务器执行，即使同屏弹幕很多，CPU 占用也很低。
- **原生** —— Swift 6、SwiftUI、AppKit、Core Animation，无第三方依赖。

### 支持的播放器

| 播放器 | 同步方式 | 典型精度 |
|---|---|---|
| IINA / mpv | mpv JSON IPC | ±5 ms |
| Infuse 及其他发布“正在播放”的应用 | 系统 Now Playing | 10–45 ms |
| VLC | Apple Events | 校准后约 ±60 ms |
| Safari / Chromium 系浏览器 | Apple Events + JavaScript | 取决于浏览器延迟 |
| 其他播放器 | 手动时钟（控制条与快捷键） | — |

## 系统要求

- macOS 26 或更新版本，Apple 芯片
- 构建需要 Xcode 26 或更新版本

## 安装

不提供预编译版本，请在仓库根目录从源码构建：

```sh
xcodebuild -project DanmakuOverlay.xcodeproj -scheme DanmakuOverlay \
  -configuration Release -derivedDataPath build build
open build/Build/Products/Release/DanmakuOverlay.app
```

也可以用 Xcode 打开 `DanmakuOverlay.xcodeproj`，运行 `DanmakuOverlay` scheme。

App 默认使用 ad-hoc 签名和占位 Bundle ID。macOS 按代码签名记录辅助功能权限，重新构建后可能需要重新授权；如需保留，请使用你自己的签名身份，见[签名](docs/DEVELOPMENT.md#signing)（英文）。

## 使用

1. 点击菜单栏图标 › **Open Danmaku…** 选择弹幕文件，或把文件拖到浮动控制条上。
2. 选择 **Attach to Window** 并选中播放器窗口，或按 ⌃⌥A 跟随最前面的播放器。同步方式会自动选择，也可以在菜单中切换。
3. 若弹幕早了或晚了，用 −/+ 按钮或 ⌃⌥[ / ⌃⌥] 调整偏移。

### 快捷键

| 快捷键 | 功能 |
|---|---|
| ⌃⌥D | 显示 / 隐藏弹幕 |
| ⌃⌥P | 播放 / 暂停 |
| ⌃⌥← / ⌃⌥→ | 快退 / 快进 |
| ⌃⌥[ / ⌃⌥] | 弹幕提前 / 延后 |
| ⌃⌥H | 显示 / 隐藏浮动控制条 |
| ⌃⌥A | 跟随最前面的播放器 |

### 各播放器设置

- **IINA**（推荐）：IINA › 设置 › 高级 › 额外 mpv 选项，添加 `input-ipc-server=/tmp/danmakuoverlay-mpv.sock`。
  - 也可以退出 IINA 后，在 DanmakuOverlay 的菜单或设置中选择 **Configure IINA**。它会把同一选项写入 IINA 的偏好设置并开启 IINA 的高级设置；如需撤销，在 IINA 设置中删除该选项即可。
  - 未配置时会退回 Now Playing。
- **mpv**：在 `mpv.conf` 中加入同一行。
- **Infuse**：无需设置。若 Now Playing 不可用，可使用手动时钟：在控制条上对齐一次进度，之后在 Infuse 中按空格、←/→ 会被同步镜像（需要辅助功能权限）。
- **VLC**：系统询问时，允许 DanmakuOverlay 控制 VLC。
- **Safari / Chrome**：系统询问时，允许 DanmakuOverlay 控制浏览器，并在浏览器中开启“允许来自 Apple 事件的 JavaScript”（Safari：设置 › 高级 › 显示网页开发者功能，然后 开发 › 允许来自 Apple 事件的 JavaScript）。

### 权限

| 权限 | 用途 | 未授予时 |
|---|---|---|
| 辅助功能 | 流畅跟随窗口、读取窗口标题、镜像按键 | 改用轮询方式跟随窗口 |
| 自动化（逐个应用） | VLC、浏览器同步 | 该同步方式不可用，改用其他方式 |

不需要“屏幕录制”权限。

## 限制

- 浏览器同步无法读取跨域 iframe 中的视频，会改用 Now Playing。
- IINA 同时打开多个窗口时，只同步最后打开的一个。
- VLC 不报告播放速率，按 1× 处理。
- 不支持 M7 高级弹幕的路径动画。
- Now Playing 同步和窗口跟随依赖 macOS 私有 API（`MediaRemote`、`_AXUIElementGetWindow`），因此无法通过 Mac App Store 分发，未来的 macOS 版本也可能使这些功能失效。

## 参与贡献

欢迎提交 Issue 和 Pull Request。架构、测试与代码规范见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)（英文）。

## 致谢

- [DanmakuPlayer](https://github.com/Poker-sang/DanmakuPlayer) —— 弹幕布局、高级弹幕及 B 站格式解析移植自该项目。
- [pakku.js](https://github.com/xmcp/pakku.js) —— 相似弹幕合并算法与拼音表。

## 免责声明

DanmakuOverlay 是独立项目，与 Bilibili、IINA、Infuse、VLC 及文中提及的其他产品无关，也未获其认可；相关名称均为其各自所有者的商标。本应用不下载、不提供任何弹幕内容，弹幕文件由用户自行提供，版权归原作者所有。

## 许可证

[GPL-3.0-only](LICENSE)。第三方署名见 [NOTICE](NOTICE)。
