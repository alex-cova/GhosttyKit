import Foundation

/// Options for a single terminal surface (one PTY, one Metal view).
public struct GhosttySurfaceConfiguration: Sendable, Equatable {
    /// Working directory for the child process. `nil` uses the user's home directory.
    public var workingDirectory: URL?

    /// Command to run. `nil` uses the user's login shell.
    public var command: String?

    /// Font size in points. `0` inherits Ghostty's config / defaults.
    public var fontSize: Double

    /// Text written to the PTY after the shell starts.
    public var initialInput: String?

    /// Keep the surface open after the child exits so the user can read the output.
    public var waitAfterCommand: Bool

    /// When false (the default), OSC 52 clipboard writes from the child are denied
    /// unless the host implements `GhosttySession.onConfirmClipboardWrite`.
    public var allowsUnconfirmedClipboardWrites: Bool

    public init(
        workingDirectory: URL? = nil,
        command: String? = nil,
        fontSize: Double = 0,
        initialInput: String? = nil,
        waitAfterCommand: Bool = false,
        allowsUnconfirmedClipboardWrites: Bool = false
    ) {
        self.workingDirectory = workingDirectory
        self.command = command
        self.fontSize = fontSize
        self.initialInput = initialInput
        self.waitAfterCommand = waitAfterCommand
        self.allowsUnconfirmedClipboardWrites = allowsUnconfirmedClipboardWrites
    }
}
