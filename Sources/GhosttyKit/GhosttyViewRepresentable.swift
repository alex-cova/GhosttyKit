import AppKit
import SwiftUI

struct GhosttyViewRepresentable: NSViewRepresentable {
    let session: GhosttySession
    let configuration: GhosttySurfaceConfiguration

    func makeNSView(context: Context) -> GhosttySurfaceView {
        GhosttySurfaceView(session: session, configuration: configuration)
    }

    func updateNSView(_ nsView: GhosttySurfaceView, context: Context) {
        nsView.session = session
    }

    static func dismantleNSView(_ nsView: GhosttySurfaceView, coordinator: ()) {
        nsView.teardown()
    }
}
