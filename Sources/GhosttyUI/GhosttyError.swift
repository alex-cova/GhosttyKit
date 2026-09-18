import Foundation

/// Errors raised while starting or driving libghostty.
public enum GhosttyError: Error, Equatable, Sendable {
    /// `Vendor/GhosttyKit.xcframework` is not present, so this build of GhosttyUI
    /// was compiled without libghostty.
    case kitMissing

    /// `ghostty_init` or `ghostty_app_new` failed.
    case runtimeFailed(String)

    /// Creating a terminal surface failed (usually a bad working directory or command).
    case surfaceFailed
}

extension GhosttyError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .kitMissing:
            return "libghostty is not linked. Run Scripts/build-ghosttykit.sh in the GhosttyUI package."
        case .runtimeFailed(let message):
            return message
        case .surfaceFailed:
            return "Ghostty could not create a terminal surface."
        }
    }
}
