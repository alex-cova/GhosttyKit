import Foundation

/// Observable state for one terminal. Own this with `@State` in SwiftUI and pass
/// it to `GhosttyView`. Creating a session does not start a shell; the PTY is
/// created when the view appears and destroyed when it disappears.
@MainActor
@Observable
public final class GhosttySession {
    public var title = "Terminal"
    public var currentDirectory: URL?
    public var isProcessRunning = true
    public var exitCode: Int32?
    public var bellCount = 0
    public var hoveredLink: String?
    public var lastError: GhosttyError?

    /// Called for http(s) links. The default opens them with `NSWorkspace`.
    public var onOpenURL: ((URL) -> Void)?

    /// Host should open another terminal tab. Returning from this does not
    /// create a surface by itself.
    public var onRequestNewTab: (() -> Void)?

    public var onRequestNewWindow: (() -> Void)?

    /// `processAlive` is true when the shell is still running.
    public var onClose: ((_ processAlive: Bool) -> Void)?

    public var onBell: (() -> Void)?

    /// Optional confirmation for OSC 52 clipboard writes. Return true to allow.
    public var onConfirmClipboardWrite: ((String) -> Bool)?

    public var configuration: GhosttySurfaceConfiguration

    @ObservationIgnored
    var attachedSurface: GhosttySurfaceAttaching?

    @ObservationIgnored
    private var pendingText: [String] = []

    public init(configuration: GhosttySurfaceConfiguration = GhosttySurfaceConfiguration()) {
        self.configuration = configuration
        self.currentDirectory = configuration.workingDirectory
    }

    /// Paste semantics: the text is written to the PTY with bracketed-paste framing
    /// when the child has enabled it. Does not synthesize key events.
    public func sendText(_ text: String) {
        if let attachedSurface {
            attachedSurface.sendText(text)
        } else if !text.isEmpty {
            pendingText.append(text)
        }
    }

    /// Ask libghostty to close the surface. The host still owns the SwiftUI view.
    public func requestClose() {
        attachedSurface?.requestClose()
    }

    func attach(_ surface: GhosttySurfaceAttaching) {
        attachedSurface = surface
        if !pendingText.isEmpty {
            let queued = pendingText
            pendingText.removeAll()
            for chunk in queued {
                surface.sendText(chunk)
            }
        }
    }

    func detach(_ surface: GhosttySurfaceAttaching) {
        if attachedSurface === surface {
            attachedSurface = nil
            isProcessRunning = false
        }
    }
}

@MainActor
protocol GhosttySurfaceAttaching: AnyObject {
    func sendText(_ text: String)
    func requestClose()
}
