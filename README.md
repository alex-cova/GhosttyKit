# GhosttyKit

SwiftUI bindings for [Ghostty](https://github.com/ghostty-org/ghostty). Drop a real libghostty terminal into a macOS app.

Repository: [github.com/alex-cova/GhosttyKit](https://github.com/alex-cova/GhosttyKit)

```swift
import GhosttyKit

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
Sources/GhosttyKit/      SwiftUI view, session, AppKit surface, FFI
Examples/GhosttyKitDemo/ Sample window
Scripts/                 Build GhosttyKit.xcframework
Vendor/                  Installed XCFramework (gitignored, ~140MB)
```

## First-time setup

The Swift package compiles without libghostty. Until the XCFramework is present, `GhosttyView` shows a placeholder and `GhosttyRuntime.isAvailable` is `false`.

```sh
git clone git@github.com:alex-cova/GhosttyKit.git
cd GhosttyKit
chmod +x Scripts/build-ghosttykit.sh Scripts/shims/metallib
./Scripts/build-ghosttykit.sh
swift run GhosttyKitDemo
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

You need Xcode (not only Command Line Tools). Homebrew `gettext` is installed automatically if missing. Xcode 26 no longer ships `metallib`; `Scripts/shims/metallib` stands in for it.

On Xcode SDK 26.4 or newer (including Xcode 27 beta), the script installs Homebrew `zig@0.15` automatically. The official Zig 0.15.2 download cannot link against Apple's newer `libSystem` stubs on those SDKs. SDK 27 also applies a small Ghostty `math.h` overlay so Zig's bundled libc++ can compile.

## SwiftPM

`Package.swift` checks for `Vendor/GhosttyKit.xcframework` at resolve time. If it is present, the package links libghostty and defines `GHOSTTYKIT_HAS_KIT`. If not, the Swift sources still compile and the placeholder view is used.

Add the dependency:

```swift
dependencies: [
    .package(url: "https://github.com/alex-cova/GhosttyKit.git", branch: "main")
]
```

For local development:

```swift
dependencies: [
    .package(path: "../GhosttyKit")
]
```

Use the library product in your target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "GhosttyKit", package: "GhosttyKit")
    ]
)
```

After adding the package, run `./Scripts/build-ghosttykit.sh` inside the GhosttyKit checkout (or place a prebuilt `Vendor/GhosttyKit.xcframework` there) before expecting a live terminal.

### Publishing

Do not commit the XCFramework to git. Attach `Vendor/GhosttyKit.xcframework.zip` to a GitHub Release, then point consumers at that artifact with a remote `binaryTarget` named `GhosttyKitXCFramework`:

```swift
.binaryTarget(
    name: "GhosttyKitXCFramework",
    url: "https://github.com/alex-cova/GhosttyKit/releases/download/0.1.0/GhosttyKit.xcframework.zip",
    checksum: "<checksum from the build script>"
)
```

The Swift target should depend on `GhosttyKitXCFramework` and define `GHOSTTYKIT_HAS_KIT` when the binary is linked. This repository's `Package.swift` already does that for a local `Vendor/GhosttyKit.xcframework`.

## CI

This repository builds and tests on `macos-15` with Xcode 16.4 via [`.github/workflows/ci.yml`](.github/workflows/ci.yml). Ghostty v1.3.0 needs the macOS 15 SDK; older GitHub-hosted images (for example `macos-14` / Xcode 15.4) fail with missing CoreVideo symbols. CI caches Ghostty's Zig package downloads under `.zig-global-cache` and retries fetches from `deps.files.ghostty.org` when the network is flaky. Tagged releases can attach `GhosttyKit.xcframework.zip` through [`.github/workflows/release-xcframework.yml`](.github/workflows/release-xcframework.yml).

Consumer apps (for example [Umbra](https://github.com/alex-cova/Penumbra)) should resolve the package, build libghostty inside the SPM checkout, then compile:

```sh
swift package resolve
./Scripts/ci-prepare-swiftpm-checkout.sh   # from GhosttyKit, or the consumer wrapper
swift build
```

Penumbra wraps that in `Scripts/prepare-ghosttykit.sh` and runs it from Umbra CI before `swift build --product Umbra`.

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
- `isAvailable` is compile-time (`GHOSTTYKIT_HAS_KIT`)

The PTY is created when the view appears and destroyed when SwiftUI dismantles it. Hold the `GhosttySession` in `@State` so layout changes do not spawn a new shell.

### OSC 8 links

Terminal-produced links only open `http` and `https`. `file:`, `javascript:`, and custom schemes are denied. Override `session.onOpenURL` if the host wants a different policy.

### Clipboard

Normal paste reads `NSPasteboard`. OSC 52 writes that require confirmation are denied unless `allowsUnconfirmedClipboardWrites` is true or `onConfirmClipboardWrite` returns true.

## What this package does not do

Ghostty's GUI owns tabs, splits, menus, config windows, and the inspector. Those stay in the host app. `GHOSTTY_ACTION_NEW_TAB` / `NEW_WINDOW` become session callbacks so you can implement them.

## Migrating from GhosttyUI

This project was renamed from GhosttyUI. Update your dependency URL or path, then replace:

- `import GhosttyUI` → `import GhosttyKit`
- `.product(name: "GhosttyUI", package: "GhosttyUI")` → `.product(name: "GhosttyKit", package: "GhosttyKit")`
- `GHOSTTYUI_HAS_KIT` → `GHOSTTYKIT_HAS_KIT` (if you mirror compile flags in your own build)

## License

MIT. Ghostty itself is also MIT; you must preserve its notices when you distribute `GhosttyKit`.
