import AppKit
import Foundation

/// Open URLs that originated in terminal output (OSC 8, printed paths, etc.).
public enum GhosttyURLPolicy: Sendable {
    public enum Decision: Equatable, Sendable {
        case allow(URL)
        case deny(String)
    }

    /// Allow http(s) only. Local files, custom schemes, and javascript are denied
    /// because OSC 8 links are producer-controlled terminal output.
    public static func decide(_ value: String) -> Decision {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            return .deny("Not a valid URL.")
        }
        switch scheme {
        case "http", "https":
            return .allow(url)
        default:
            return .deny("Blocked \(scheme) URL from the terminal.")
        }
    }

    @MainActor
    public static func open(_ value: String) -> Bool {
        switch decide(value) {
        case .allow(let url):
            return NSWorkspace.shared.open(url)
        case .deny:
            return false
        }
    }
}
