import SwiftUI

/// Shown on an iPad's external display while no document is open (DOC-05, changed):
/// the app logo and a short text on black, so the audience sees the display is in use.
struct ReadyToPresentView: View {
    var body: some View {
        AudienceMessageView(message: Text("Ready to present"))
    }
}

/// The app logo and a short message on black, for an audience screen that shows no deck:
/// the ready screen, or the end of the trial (PRO-03).
struct AudienceMessageView: View {
    let message: Text
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
                message
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
