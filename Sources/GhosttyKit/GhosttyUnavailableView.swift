import SwiftUI

struct GhosttyUnavailableView: View {
    var body: some View {
        ContentUnavailableView(
            "libghostty is not linked",
            systemImage: "apple.terminal",
            description: Text("Run Scripts/build-ghosttykit.sh in the GhosttyKit package, then rebuild. Until GhosttyKit.xcframework is present, this view is a placeholder.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

#Preview {
    GhosttyUnavailableView()
        .frame(width: 640, height: 360)
        .preferredColorScheme(.dark)
}
