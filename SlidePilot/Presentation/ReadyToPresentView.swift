import SwiftUI

/// Shown on an iPad's external display while no document is open (DOC-05, changed):
/// the app logo and a short text on black, so the audience sees the display is in use.
struct ReadyToPresentView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var logoWidth = 160
    @ScaledMetric(relativeTo: .largeTitle) private var spacing = 24

    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: spacing) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: logoWidth)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Ready to present")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .ignoresSafeArea()
        // The display is black in light and dark mode.
        .environment(\.colorScheme, .dark)
    }
}

#Preview {
    ReadyToPresentView()
}
