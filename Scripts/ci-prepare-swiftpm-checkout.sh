#!/usr/bin/env bash
# Build Vendor/GhosttyKit.xcframework inside a SwiftPM GhosttyKit checkout.
#
# Usage (from a consumer repo such as Penumbra/Umbra):
#   swift package resolve
#   /path/to/GhosttyKit/Scripts/ci-prepare-swiftpm-checkout.sh
#
# Or from the GhosttyKit repo root:
#   ./Scripts/ci-prepare-swiftpm-checkout.sh
set -euo pipefail

consumer_root="$(pwd)"
checkout="${GHOSTTYKIT_CHECKOUT:-}"

if [[ -z "$checkout" ]]; then
    if [[ -f "$consumer_root/Package.swift" ]] && grep -q 'name: "GhosttyKit"' "$consumer_root/Package.swift" 2>/dev/null; then
        checkout="$consumer_root"
    else
        checkout="$(find "$consumer_root/.build/checkouts" -maxdepth 1 -type d -iname 'ghosttykit*' 2>/dev/null | head -n 1 || true)"
    fi
fi

[[ -n "$checkout" ]] || {
    echo "error: GhosttyKit checkout not found under $consumer_root/.build/checkouts" >&2
    echo "run 'swift package resolve' in the consumer package first" >&2
    exit 1
}

chmod +x "$checkout/Scripts/build-ghosttykit.sh" "$checkout/Scripts/shims/metallib"
exec "$checkout/Scripts/build-ghosttykit.sh"
