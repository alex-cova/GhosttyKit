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

ensure_zig() {
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

ensure_gettext() {
    if command -v brew >/dev/null 2>&1; then
        if ! brew list gettext >/dev/null 2>&1; then
            log "installing gettext via Homebrew (Ghostty build dependency)"
            brew install gettext
        fi
    fi
}

clone_ghostty() {
    if [[ -d "$SRC_DIR/.git" ]]; then
        log "updating Ghostty in $SRC_DIR ($GHOSTTY_REF)"
        git -C "$SRC_DIR" fetch --tags --depth 1 origin "$GHOSTTY_REF" || \
            git -C "$SRC_DIR" fetch --depth 1 origin "$GHOSTTY_REF"
        git -C "$SRC_DIR" checkout --detach FETCH_HEAD
    else
        log "cloning Ghostty $GHOSTTY_REF"
        mkdir -p "$(dirname "$SRC_DIR")"
        git clone --depth 1 --branch "$GHOSTTY_REF" "$GHOSTTY_REPO" "$SRC_DIR" \
            || git clone --depth 1 "$GHOSTTY_REPO" "$SRC_DIR"
        if ! git -C "$SRC_DIR" checkout "$GHOSTTY_REF" 2>/dev/null; then
            log "ref $GHOSTTY_REF not found locally; staying on default branch"
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
    found="$(find "$SRC_DIR/zig-out" -name 'GhosttyKit.xcframework' -type d | head -n 1)"
    if [[ -z "$found" ]]; then
        found="$(find "$SRC_DIR/zig-out" -name '*.xcframework' -type d | head -n 1)"
    fi
    [[ -n "$found" ]] || die "zig build finished but no .xcframework was found under zig-out"

    log "installing $(basename "$found") -> $KIT_DEST"
    rm -rf "$KIT_DEST"
    mkdir -p "$VENDOR_DIR"
    cp -R "$found" "$KIT_DEST"

    if [[ -f "$SRC_DIR/include/ghostty.h" ]]; then
        cp "$SRC_DIR/include/ghostty.h" "$VENDOR_DIR/ghostty.h"
    fi

    git -C "$SRC_DIR" rev-parse HEAD > "$VENDOR_DIR/GHOSTTY_REVISION"
    log "Ghostty revision $(cat "$VENDOR_DIR/GHOSTTY_REVISION")"
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
build_kit
install_kit
zip_kit

log "done. swift build will now link libghostty."
log "to publish as a SwiftPM binary target, attach Vendor/GhosttyKit.xcframework.zip to a GitHub Release."
