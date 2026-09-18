#!/usr/bin/env bash
# Build Ghostty's embeddable XCFramework (GhosttyKit) and install it into Vendor/.
#
# After this script succeeds, `swift build` links the real libghostty and
# GhosttyView renders a terminal. Until then the Swift package still compiles,
# but GhosttyView shows an unavailable placeholder.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

GHOSTTY_REF="${GHOSTTY_REF:-v1.3.0}"
GHOSTTY_REPO="${GHOSTTY_REPO:-https://github.com/ghostty-org/ghostty.git}"
ZIG_VERSION="${ZIG_VERSION:-0.15.2}"
SRC_DIR="${GHOSTTY_SRC:-$root/.build-ghostty/ghostty}"
VENDOR_DIR="$root/Vendor"
KIT_DEST="$VENDOR_DIR/GhosttyKit.xcframework"
ZIG_HOME="$root/Scripts/.zig-toolchain"

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "missing $1"; }

need git
need curl
need tar
need xcrun

if ! xcode-select -p >/dev/null 2>&1; then
    die "Xcode developer directory is not selected (xcode-select -p)"
fi

arch="$(uname -m)"
case "$arch" in
    arm64) zig_archive="zig-aarch64-macos-${ZIG_VERSION}.tar.xz" ;;
    x86_64) zig_archive="zig-x86_64-macos-${ZIG_VERSION}.tar.xz" ;;
    *) die "unsupported architecture: $arch" ;;
esac

# Apple SDK >= 26.4 only publishes arm64e libSystem stubs. Stock Zig 0.15.2
# cannot link against them, so `zig build` fails before Ghostty's build.zig runs.
# Homebrew's zig@0.15 backports the upstream Mach-O linker fix.
needs_patched_zig() {
    local sdk
    sdk="$(xcrun --show-sdk-version 2>/dev/null || true)"
    [[ -n "$sdk" ]] || return 1

    local major="${sdk%%.*}"
    local minor="${sdk#*.}"
    minor="${minor%%.*}"

    if (( major > 26 )); then
        return 0
    fi
    if (( major == 26 && minor >= 4 )); then
        return 0
    fi
    return 1
}

brew_zig_bin() {
    command -v brew >/dev/null 2>&1 || return 1
    local prefix
    prefix="$(brew --prefix "zig@${ZIG_VERSION%.*}" 2>/dev/null)" || return 1
    local bin="$prefix/bin/zig"
    [[ -x "$bin" ]] || return 1
    printf '%s\n' "$bin"
}

ensure_patched_zig() {
    local bin
    bin="$(brew_zig_bin || true)"
    if [[ -z "$bin" ]]; then
        if command -v brew >/dev/null 2>&1; then
            log "installing Homebrew zig@${ZIG_VERSION%.*} (required for Xcode SDK >= 26.4)"
            brew install "zig@${ZIG_VERSION%.*}"
            bin="$(brew_zig_bin)" || die "Homebrew zig@${ZIG_VERSION%.*} install failed"
        else
            die "Xcode SDK >= 26.4 requires Homebrew zig@${ZIG_VERSION%.*} (brew install zig@${ZIG_VERSION%.*}). Official Zig ${ZIG_VERSION} cannot link libSystem on this SDK."
        fi
    fi

    local found
    found="$("$bin" version)"
    [[ "$found" == "$ZIG_VERSION" ]] || die "Homebrew zig@${ZIG_VERSION%.*} is $found, need $ZIG_VERSION"

    export PATH="$(dirname "$bin"):$PATH"
    log "using Homebrew zig $(zig version) (patched for SDK >= 26.4)"
}

ensure_zig() {
    if needs_patched_zig; then
        ensure_patched_zig
        return
    fi

    if command -v zig >/dev/null 2>&1; then
        local found
        found="$(zig version)"
        if [[ "$found" == "$ZIG_VERSION" ]]; then
            log "using system zig $found"
            return
        fi
        log "system zig is $found, need $ZIG_VERSION"
    fi

    mkdir -p "$ZIG_HOME"
    local zig_bin="$ZIG_HOME/zig-${ZIG_VERSION}/zig"
    if [[ ! -x "$zig_bin" ]]; then
        log "downloading Zig $ZIG_VERSION"
        local url="https://ziglang.org/download/${ZIG_VERSION}/${zig_archive}"
        local alt="https://ziglang.org/download/${ZIG_VERSION}/zig-macos-${arch}-${ZIG_VERSION}.tar.xz"
        local tmp="$ZIG_HOME/zig.tar.xz"
        if ! curl -fL "$url" -o "$tmp"; then
            log "retrying alternate archive name"
            curl -fL "$alt" -o "$tmp"
        fi
        rm -rf "$ZIG_HOME/extract"
        mkdir -p "$ZIG_HOME/extract"
        tar -xJf "$tmp" -C "$ZIG_HOME/extract"
        local extracted
        extracted="$(find "$ZIG_HOME/extract" -maxdepth 2 -type f -name zig | head -n 1)"
        [[ -n "$extracted" ]] || die "zig binary missing from archive"
        mkdir -p "$ZIG_HOME/zig-${ZIG_VERSION}"
        cp -R "$(dirname "$extracted")/." "$ZIG_HOME/zig-${ZIG_VERSION}/"
        rm -rf "$ZIG_HOME/extract" "$tmp"
    fi
    export PATH="$ZIG_HOME/zig-${ZIG_VERSION}:$PATH"
    log "using zig $(zig version)"
}

needs_xcode27_math_overlay() {
    local sdk
    sdk="$(xcrun --show-sdk-version 2>/dev/null || true)"
    [[ -n "$sdk" ]] || return 1
    local major="${sdk%%.*}"
    (( major >= 27 ))
}

patch_ghostty_for_xcode27() {
    needs_xcode27_math_overlay || return 0

    local apple_sdk="$SRC_DIR/pkg/apple-sdk"
    local patch_root="$root/Scripts/patches/xcode27-apple-sdk"
    local build_zig="$apple_sdk/build.zig"

    [[ -f "$build_zig" ]] || die "missing $build_zig"

    log "patching Ghostty apple-sdk for Xcode SDK >= 27"
    mkdir -p "$apple_sdk/include"
    cp "$patch_root/include/math.h" "$apple_sdk/include/math.h"
    git -C "$SRC_DIR" checkout -- pkg/apple-sdk/build.zig

    python3 - "$build_zig" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
text = text.replace(
    "        const libc = try std.zig.LibCInstallation.findNative(.{",
    "        var libc = try std.zig.LibCInstallation.findNative(.{",
    1,
)
needle = """        });

        // Render the file compatible with the `--libc` Zig flag."""
insert = """        });

        // GHOSTTYKIT_XCODE27_MATH_OVERLAY: Xcode 27 SDK needs INFINITY/NAN for Zig libc++.
        libc.include_dir = try std.fs.path.join(b.allocator, &.{
            try std.process.getCwdAlloc(b.allocator),
            "pkg", "apple-sdk", "include",
        });

        // Render the file compatible with the `--libc` Zig flag."""
if needle not in text:
    sys.exit("could not locate apple-sdk/build.zig insertion point")
path.write_text(text.replace(needle, insert, 1))
PY

    rm -rf "$SRC_DIR/.zig-cache"
}

ensure_gettext() {
    if command -v brew >/dev/null 2>&1; then
        if ! brew list gettext >/dev/null 2>&1; then
            log "installing gettext via Homebrew (Ghostty build dependency)"
            brew install gettext
        fi
    fi
}

clone_ghostty() {
    local ref="$GHOSTTY_REF"

    if [[ -d "$SRC_DIR/.git" ]]; then
        log "updating Ghostty in $SRC_DIR ($ref)"
        if git -C "$SRC_DIR" fetch --depth 1 origin "refs/tags/$ref:refs/tags/$ref" 2>/dev/null; then
            git -C "$SRC_DIR" checkout --detach "refs/tags/$ref"
        elif git -C "$SRC_DIR" fetch --depth 1 origin "$ref"; then
            git -C "$SRC_DIR" checkout --detach FETCH_HEAD
        else
            die "could not fetch Ghostty ref $ref"
        fi
    else
        log "cloning Ghostty $ref"
        mkdir -p "$(dirname "$SRC_DIR")"
        rm -rf "$SRC_DIR"
        git clone "$GHOSTTY_REPO" "$SRC_DIR"
        if git -C "$SRC_DIR" fetch --depth 1 origin "refs/tags/$ref:refs/tags/$ref" 2>/dev/null; then
            git -C "$SRC_DIR" checkout --detach "refs/tags/$ref"
        elif git -C "$SRC_DIR" fetch --depth 1 origin "$ref"; then
            git -C "$SRC_DIR" checkout --detach FETCH_HEAD
        else
            die "could not fetch Ghostty ref $ref"
        fi
    fi
}

build_kit() {
    export PATH="$root/Scripts/shims:$PATH"
    chmod +x "$root/Scripts/shims/metallib"

    log "building GhosttyKit (this takes several minutes)"
    (
        cd "$SRC_DIR"
        zig build \
            -Demit-xcframework=true \
            -Dxcframework-target=native \
            -Demit-macos-app=false \
            -Doptimize=ReleaseFast
    )
}

install_kit() {
    local found
    found="$(find "$SRC_DIR/zig-out" "$SRC_DIR/macos" -name 'GhosttyKit.xcframework' -type d 2>/dev/null | head -n 1)"
    if [[ -z "$found" ]]; then
        found="$(find "$SRC_DIR/zig-out" "$SRC_DIR/macos" -name '*.xcframework' -type d 2>/dev/null | head -n 1)"
    fi
    [[ -n "$found" ]] || die "zig build finished but no .xcframework was found under zig-out or macos"

    log "installing $(basename "$found") -> $KIT_DEST"
    rm -rf "$KIT_DEST"
    mkdir -p "$VENDOR_DIR"
    cp -R "$found" "$KIT_DEST"

    if [[ -f "$SRC_DIR/include/ghostty.h" ]]; then
        cp "$SRC_DIR/include/ghostty.h" "$VENDOR_DIR/ghostty.h"
    fi

    git -C "$SRC_DIR" rev-parse HEAD > "$VENDOR_DIR/GHOSTTY_REVISION"
    log "Ghostty revision $(cat "$VENDOR_DIR/GHOSTTY_REVISION")"

    # SwiftPM target is GhosttyKit; rename the Clang module so it does not collide.
    local modulemap
    modulemap="$(find "$KIT_DEST" -name module.modulemap -type f | head -n 1)"
    if [[ -n "$modulemap" ]]; then
        sed -i '' 's/module GhosttyKit/module GhosttyKitC/' "$modulemap"
    fi
}

zip_kit() {
    local zip="$VENDOR_DIR/GhosttyKit.xcframework.zip"
    rm -f "$zip"
    (cd "$VENDOR_DIR" && zip -qry "$(basename "$zip")" GhosttyKit.xcframework)
    log "wrote $zip"
    if command -v swift >/dev/null 2>&1; then
        log "checksum: $(swift package compute-checksum "$zip")"
    fi
}

ensure_zig
ensure_gettext
clone_ghostty
patch_ghostty_for_xcode27
build_kit
install_kit
zip_kit

log "done. swift build will now link libghostty."
log "to publish as a SwiftPM binary target, attach Vendor/GhosttyKit.xcframework.zip to a GitHub Release."
