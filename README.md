# GhosttyUI

SwiftUI bindings for [Ghostty](https://github.com/ghostty-org/ghostty). Drop a real libghostty terminal into a macOS app:

```swift
import GhosttyUI

struct EditorTerminal: View {
    @State private var session = GhosttySession(
        configuration: GhosttySurfaceConfiguration(
            workingDirectory: projectRoot
        )
    )

    var body: some View {
        GhosttyView(session: session)
    }
}
```

`GhosttyView` is the Metal surface. Your app owns tabs, splits, chrome, and keybindings around it.

## Status

libghostty's embedder API (`ghostty.h`) is the same C API Ghostty's macOS app uses. It is **not a stable public ABI**. This package pins a Ghostty revision when you build `GhosttyKit.xcframework` and isolates every `ghostty_*` call so a header bump touches one layer.

| | |
|---|---|
| Platform | macOS 14+ |
| Swift | 6.0 |
| Terminal | libghostty (PTY, VT, Metal, fonts) |
| UI | SwiftUI `View` wrapping `NSView` |

Apple Silicon is the default XCFramework target (`-Dxcframework-target=native`). Universal builds need a different Ghostty build flag.

## Package layout

```
Sources/GhosttyUI/     SwiftUI view, session, AppKit surface, FFI
Examples/GhosttyUIDemo Sample window
Scripts/               Build GhosttyKit.xcframework
Vendor/                Installed XCFramework (gitignored, ~140MB)
```

## First-time setup

The Swift package compiles without libghostty. Until the XCFramework is present, `GhosttyView` shows a placeholder and `GhosttyRuntime.isAvailable` is `false`.

```sh
chmod +x Scripts/build-ghosttykit.sh Scripts/shims/metallib
./Scripts/build-ghosttykit.sh
swift run GhosttyUIDemo
```

The script:

1. Downloads the Zig version Ghostty requires (default `0.15.2`)
2. Clones Ghostty at `GHOSTTY_REF` (default `v1.3.0`)
3. Builds `GhosttyKit.xcframework` with `-Doptimize=ReleaseFast`
4. Copies it to `Vendor/GhosttyKit.xcframework`
5. Zips it and prints a SwiftPM checksum

Override pins as needed:

```sh
GHOSTTY_REF=v1.3.0 ZIG_VERSION=0.15.2 ./Scripts/build-ghosttykit.sh
```

You need Xcode (not only Command Line Tools), and Homebrew `gettext` is installed if missing. Xcode 26 no longer ships `metallib`; `Scripts/shims/metallib` stands in for it.

## SwiftPM

Until you publish a release, depend on a local clone:

```swift
dependencies: [
    .package(path: "../GhosttyUI")
]
```

```swift
.executableTarget(
    name: "Umbra",
    dependencies: [
        .product(name: "GhosttyUI", package: "GhosttyUI")
    ]
)
```

### Publishing

Do not commit the XCFramework to git. Attach `Vendor/GhosttyKit.xcframework.zip` to a GitHub Release, then switch `Package.swift` to:

```swift
.binaryTarget(
    name: "GhosttyKit",
    url: "https://github.com/<you>/GhosttyUI/releases/download/0.1.0/GhosttyKit.xcframework.zip",
    checksum: "<checksum from the build script>"
)
```

Keep `GHOSTTYUI_HAS_KIT` defined on the `GhosttyUI` target whenever `GhosttyKit` is linked.

## API

**`GhosttyView`**

- `GhosttyView(configuration:)` for a self-contained terminal
- `GhosttyView(session:)` when the host needs title, cwd, and send-text

**`GhosttySession`** (`@Observable`, `@MainActor`)

- `title`, `currentDirectory`, `isProcessRunning`, `exitCode`, `bellCount`
- `sendText(_:)` (paste semantics, including bracketed paste)
- `onOpenURL`, `onRequestNewTab`, `onRequestNewWindow`, `onClose`, `onBell`
- `onConfirmClipboardWrite` for OSC 52

**`GhosttySurfaceConfiguration`**

- `workingDirectory`, `command`, `fontSize`, `initialInput`, `waitAfterCommand`
- `allowsUnconfirmedClipboardWrites` defaults to `false`

**`GhosttyRuntime`**

- Shared `ghostty_app_t` for the process
- `isAvailable` is compile-time (`GHOSTTYUI_HAS_KIT`)

The PTY is created when the view appears and destroyed when SwiftUI dismantles it. Hold the `GhosttySession` in `@State` so layout changes do not spawn a new shell.

### OSC 8 links

Terminal-produced links only open `http` and `https`. `file:`, `javascript:`, and custom schemes are denied. Override `session.onOpenURL` if the host wants a different policy.

### Clipboard

Normal paste reads `NSPasteboard`. OSC 52 writes that require confirmation are denied unless `allowsUnconfirmedClipboardWrites` is true or `onConfirmClipboardWrite` returns true.

## What this package does not do

Ghostty's GUI owns tabs, splits, menus, config windows, and the inspector. Those stay in the host (Umbra, your app). `GHOSTTY_ACTION_NEW_TAB` / `NEW_WINDOW` become session callbacks so you can implement them.

## License

MIT. Ghostty itself is also MIT; you must preserve its notices when you distribute `GhosttyKit`.
