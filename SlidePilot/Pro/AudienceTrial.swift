import SlidePilotCore
import SwiftUI

// The trial of the audience output (PRO-03, ADR 0020): the banner and the end on the
// audience screen, the purchase offer on the presenter. `AudienceOutputTrial` (Core) holds
// the rules; in the free Mac download its status is unlimited, so nothing here shows.

extension View {
    /// Shows the trial on an audience screen: the "SlidePilot – Trial Version" banner while it
    /// runs and, once it is over, a black screen with "Trial Ended" instead of the deck (with
    /// its pointer, drawing and curtain). Forwards the Pro status, so buying Pro lifts the
    /// limit at once.
    func audienceTrial(_ trial: AudienceOutputTrial?) -> some View {
        modifier(AudienceTrialModifier(trial: trial))
    }

    /// Shows the purchase offer on the presenter when the audience output starts and when its
    /// trial ends, once per session each. `isShownHere` picks the one presenter window that
    /// shows it when several documents are open.
    func audienceTrialOffer(_ trial: AudienceOutputTrial?, isShownHere: Bool = true) -> some View {
        modifier(AudienceTrialOfferModifier(trial: trial, isShownHere: isShownHere))
    }
}

private struct AudienceTrialModifier: ViewModifier {
    let trial: AudienceOutputTrial?
    @Environment(ProStore.self) private var pro

    func body(content: Content) -> some View {
        Group {
            if trial?.hidesOutput == true {
                AudienceMessageView(message: Text("Trial Ended", comment: "When a trial is over: the title of the purchase offer's reason line, and the message on the audience screen."))
            } else {
                content
            }
        }
        .overlay(alignment: .top) {
            if trial?.showsBanner == true {
                TrialBanner()
            }
        }
        .onChange(of: pro.status, initial: true) { _, status in
            trial?.statusChanged(status)
        }
    }
}

/// "SlidePilot – Trial Version" at the top of the audience screen. Part of the slide surface
/// (custom UI allowed there, ADR 0010): a capsule of system material with a semantic font,
/// large enough to read from the room, small enough to leave the slide readable.
private struct TrialBanner: View {
    @ScaledMetric(relativeTo: .title) private var horizontalPadding = 24
    @ScaledMetric(relativeTo: .title) private var verticalPadding = 10
    @ScaledMetric(relativeTo: .title) private var topPadding = 16

    var body: some View {
        Text("SlidePilot – Trial Version", comment: "Banner on the audience screen while the 3-minute trial of SlidePilot Pro runs.")
            .font(.title.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(.regularMaterial, in: .capsule)
            .padding(.top, topPadding)
            // The audience screen is dark in light and dark mode.
            .environment(\.colorScheme, .dark)
            .allowsHitTesting(false)
    }
}

private struct AudienceTrialOfferModifier: ViewModifier {
    let trial: AudienceOutputTrial?
    let isShownHere: Bool
    @State private var reason: ProOfferReason?
    @Environment(ProStore.self) private var pro

    func body(content: Content) -> some View {
        content
            // Also here, so a purchase reaches the trial while no audience view is shown
            // (e.g. the iPad display unplugged during the reconnect grace).
            .onChange(of: pro.status, initial: true) { _, status in
                trial?.statusChanged(status)
            }
            .onChange(of: isShownHere ? trial?.pendingOffer : nil, initial: true) { _, offer in
                guard let offer, let trial else { return }
                switch offer {
                case .started: reason = .audienceOutputStarted
                case .ended: reason = .trialEnded(.audienceOutput)
                }
                trial.offerShown(offer)
            }
            // On a view of its own: the presenter chains other sheets on the same view, and
            // of several sheets on one view only one presents.
            .background {
                Color.clear
                    .proOffer(reason: $reason)
            }
    }
}

#if os(iOS)
extension View {
    /// The external display's purchase offer on the presenter whose document the display
    /// shows: the active window's (iPadOS), the only one on the iPhone.
    func externalDisplayTrialOffer(_ session: PresentationSession) -> some View {
        modifier(ExternalDisplayTrialOfferModifier(session: session))
    }
}

private struct ExternalDisplayTrialOfferModifier: ViewModifier {
    let session: PresentationSession
    @Environment(SessionRegistry.self) private var registry
    @Environment(AudienceOutputTrial.self) private var trial: AudienceOutputTrial?

    func body(content: Content) -> some View {
        content.audienceTrialOffer(trial, isShownHere: registry.activeSession?.id == session.id)
    }
}
#endif
