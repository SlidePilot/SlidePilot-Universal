import SlidePilotCore
import SwiftUI

/// What differs between the App Store build and the free Mac download (ADR 0011).
enum ProductEdition {
    /// Only `Config/FreeDownload.xcconfig` sets the flag; the App Store build (Mac and iPad)
    /// never shows the donation hint (DROP-03). The views below are compiled in every build,
    /// so they and their strings stay checked, but only the free download turns them on.
    #if SLIDEPILOT_FREE_DOWNLOAD
    static let showsDonationHint = true
    #else
    static let showsDonationHint = false
    #endif
}

/// "Support SlidePilot" in the app menu, below About (DROP-03). Free download only.
struct DonationCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            if ProductEdition.showsDonationHint {
                SupportSlidePilotButton()
            }
        }
    }
}

private struct SupportSlidePilotButton: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button(String(localized: "Support SlidePilot", comment: "App menu item of the free Mac download; opens the donation page.")) {
            openURL(DonationHint.donationURL)
        }
    }
}

extension View {
    /// Asks once, after the fifth launch, for a donation (DROP-03). Does nothing without a
    /// hint, that is in the App Store build.
    func donationHint(_ hint: DonationHint?) -> some View {
        modifier(DonationHintModifier(hint: hint))
    }
}

private struct DonationHintModifier: ViewModifier {
    let hint: DonationHint?
    @State private var isPresented = false
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content
            .task {
                guard let hint else { return }
                // Like the old app: a moment after the presenter appears, not over the
                // window while it opens.
                try? await Task.sleep(for: .seconds(1.2))
                guard !Task.isCancelled, hint.presentIfDue() else { return }
                isPresented = true
            }
            .alert(
                Text("Do you like SlidePilot?", comment: "Title of the donation hint in the free Mac download."),
                isPresented: $isPresented
            ) {
                Button(String(localized: "Donate", comment: "Button of the donation hint; opens the donation page.")) {
                    openURL(DonationHint.donationURL)
                }
                Button(String(localized: "Not Now"), role: .cancel) {}
            } message: {
                Text(
                    "If you do, we would be very happy if you supported SlidePilot with a small donation and told others about the app.",
                    comment: "Message of the donation hint in the free Mac download."
                )
            }
    }
}
