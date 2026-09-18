import SwiftUI

/// SwiftUI terminal view backed by libghostty.
///
/// ```swift
/// @State private var session = GhosttySession(
///     configuration: GhosttySurfaceConfiguration(workingDirectory: projectURL)
/// )
///
/// var body: some View {
///     GhosttyView(session: session)
/// }
/// ```
///
/// The shell starts when the view appears and is destroyed when it disappears.
/// Keep the same `GhosttySession` instance across layout changes that would
/// otherwise recreate the view identity.
public struct GhosttyView: View {
    @State private var ownedSession = GhosttySession()
    private let externalSession: GhosttySession?
    private let configuration: GhosttySurfaceConfiguration?

    public init(configuration: GhosttySurfaceConfiguration = GhosttySurfaceConfiguration()) {
        self.externalSession = nil
        self.configuration = configuration
        self._ownedSession = State(initialValue: GhosttySession(configuration: configuration))
    }

    public init(session: GhosttySession) {
        self.externalSession = session
        self.configuration = nil
    }

    private var session: GhosttySession {
        externalSession ?? ownedSession
    }

    private var resolvedConfiguration: GhosttySurfaceConfiguration {
        configuration ?? session.configuration
    }

    public var body: some View {
        Group {
            if GhosttyRuntime.isAvailable {
                GhosttyViewRepresentable(session: session, configuration: resolvedConfiguration)
            } else {
                GhosttyUnavailableView()
            }
        }
    }
}
