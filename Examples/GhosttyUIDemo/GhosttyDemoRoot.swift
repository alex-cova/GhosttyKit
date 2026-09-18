import GhosttyUI
import SwiftUI

struct GhosttyDemoRoot: View {
    @State private var session = GhosttySession(
        configuration: GhosttySurfaceConfiguration(
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    )

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(session.title)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if let directory = session.currentDirectory {
                    Text(directory.path)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            GhosttyView(session: session)
        }
        .background(.black)
        .navigationTitle(session.title)
    }
}

#Preview {
    GhosttyDemoRoot()
        .frame(width: 800, height: 500)
        .preferredColorScheme(.dark)
}
