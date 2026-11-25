import SlidePilotCore
import SwiftUI

// The purchase offer, the trial hint and the Pro section of Settings (PRO-05, ADR 0020).
// Everything below compiles in both editions; the free Mac download gets the empty versions
// at the end of the file, so no other file needs an `#if` and that build has no StoreKit code.

/// Why the purchase offer is shown; the offer puts it above the product.
enum ProOfferReason: Hashable, Sendable, Identifiable {
    /// An external display connected or a presentation window opened (PRO-03).
    case audienceOutputStarted
    /// Remote mode started or this device is controlled for the first time (PRO-04).
    case remoteControlStarted
    /// A trial session reached its 3 minutes (PRO-03, PRO-04).
    case trialEnded(LimitedFeature)

    var id: Self { self }

    var title: Text {
        switch self {
        case .audienceOutputStarted, .remoteControlStarted:
            Text("Trial Version", comment: "Title of the purchase offer's reason line when a trial starts.")
        case .trialEnded:
            Text("Trial Ended", comment: "Title of the purchase offer's reason line when a trial is over.")
        }
    }

    var message: Text {
        switch self {
        case .audienceOutputStarted:
            Text("Without SlidePilot Pro, the audience sees the slides for 3 minutes each time you start presenting.")
        case .remoteControlStarted:
            Text("Without SlidePilot Pro, each remote connection lasts 3 minutes.")
        case .trialEnded(.audienceOutput):
            Text("The 3 minutes of presenting are over. Unlock SlidePilot Pro to present without a time limit.")
        case .trialEnded(.remoteControl):
            Text("The 3 minutes of remote control are over. Unlock SlidePilot Pro to control without a time limit.")
        }
    }
}

extension View {
    /// Shows the purchase offer of SlidePilot Pro as a sheet while `isPresented` is true. The
    /// same sheet serves every place that offers Pro; `reason` adds a line above the product.
    func proOffer(isPresented: Binding<Bool>, reason: ProOfferReason? = nil) -> some View {
        modifier(ProOfferModifier(isPresented: isPresented, reason: reason))
    }

    /// Shows the purchase offer with the given reason while `reason` is not `nil`; closing the
    /// offer sets it back to `nil`.
    func proOffer(reason: Binding<ProOfferReason?>) -> some View {
        proOffer(
            isPresented: Binding(get: { reason.wrappedValue != nil }, set: { if !$0 { reason.wrappedValue = nil } }),
            reason: reason.wrappedValue
        )
    }

    /// The trial hint at the top of the presenter while Pro is missing; it opens the offer.
    func trialHint() -> some View {
        modifier(TrialHintModifier())
    }
}

#if !SLIDEPILOT_FREE_DOWNLOAD

import StoreKit

private struct ProOfferModifier: ViewModifier {
    @Binding var isPresented: Bool
    let reason: ProOfferReason?

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            ProOfferView(reason: reason)
        }
    }
}

/// The purchase offer: StoreKit's own product view, what Pro unlocks and Restore Purchases.
struct ProOfferView: View {
    let reason: ProOfferReason?
    /// Closes the offer where UIKit presented it (launch screen); `nil` in a SwiftUI sheet.
    var close: (() -> Void)?
    @Environment(ProStore.self) private var pro
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(macOS)
        // A plain macOS sheet: the form and a Close button below it, in one layout. A toolbar
        // (NavigationStack) loses its bottom bar after StoreKit's purchase sheet closed, which
        // left no way to close the offer; the button here cannot get lost and the sheet's
        // height follows the form, also when the purchase makes it shorter.
        VStack(spacing: 0) {
            form
                .scrollBounceBehavior(.basedOnSize)
            HStack {
                Spacer()
                closeButton
            }
            .padding()
        }
        .frame(minWidth: 420, idealWidth: 480, maxWidth: 560)
        .presentationSizing(.fitted)
        #else
        NavigationStack {
            form
                .navigationTitle("SlidePilot Pro")
                .navigationBarTitleDisplayMode(.inline)
                // The document's navigation would otherwise add a back button to the sheet.
                .navigationBarBackButtonHidden()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        closeButton
                    }
                }
        }
        #endif
    }

    private var form: some View {
        Form {
            if let reason, !pro.status.unlocksEverything {
                Section {
                    Label {
                        VStack(alignment: .leading) {
                            reason.title
                                .font(.headline)
                            reason.message
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "clock")
                    }
                }
            }
            ProProductSection(style: .large) { EmptyView() } extra: { RestorePurchasesButton() }
            Section("Included in SlidePilot Pro") {
                Label("Present on external displays, AirPlay and presentation windows without a time limit", systemImage: "rectangle.on.rectangle")
                Label("Control and be controlled by other devices without a time limit", systemImage: "appletvremote.gen4")
                Label("No trial banner on the audience screen", systemImage: "eye.slash")
            }
        }
        .formStyle(.grouped)
    }

    private var closeButton: some View {
        Button(role: .close) {
            if let close { close() } else { dismiss() }
        }
        // Escape closes it with a hardware keyboard.
        .keyboardShortcut(.cancelAction)
    }
}

/// SlidePilot Pro as StoreKit shows it, or that it is unlocked, in a form section. Buying
/// from here goes through `ProStore`, which verifies and finishes the transaction.
private struct ProProductSection<Header: View, Extra: View>: View {
    let style: Style
    @ViewBuilder let header: Header
    /// More rows below the product while Pro is missing (Restore Purchases in Settings).
    @ViewBuilder let extra: Extra
    @Environment(ProStore.self) private var pro
    @State private var alert: ProPurchaseAlert?

    enum Style { case large, compact }

    var body: some View {
        Section {
            if pro.status.unlocksEverything {
                Label {
                    Text("SlidePilot Pro is unlocked. Thank you!")
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.tint)
                }
            } else {
                if let productID = pro.productID {
                    product(productID)
                        .onInAppPurchaseCompletion { _, result in
                            await complete(result)
                        }
                } else {
                    Text("SlidePilot Pro cannot be bought in this build.")
                        .foregroundStyle(.secondary)
                }
                extra
            }
        } header: {
            header
        } footer: {
            if !pro.status.unlocksEverything {
                Text("One purchase for Mac, iPad and iPhone, shared with your family.")
            }
        }
        .proPurchaseAlert($alert)
    }

    @ViewBuilder
    private func product(_ productID: String) -> some View {
        let view = ProductView(id: productID) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
        }
        switch style {
        // The large style sizes to its content and would sit off center in the row.
        case .large: view.productViewStyle(.large).frame(maxWidth: .infinity)
        case .compact: view.productViewStyle(.compact)
        }
    }

    private func complete(_ result: Result<Product.PurchaseResult, any Error>) async {
        do {
            if try await pro.completePurchase(result) == .pending {
                alert = .pending
            }
        } catch StoreKitError.userCancelled {
            // Nothing to say: the user cancelled.
        } catch {
            alert = .failed(error.localizedDescription)
        }
    }
}

/// Restore Purchases (PRO-02): syncs with the App Store, which may ask to sign in.
private struct RestorePurchasesButton: View {
    @Environment(ProStore.self) private var pro
    @State private var isRestoring = false
    @State private var alert: ProPurchaseAlert?

    var body: some View {
        Button("Restore Purchases") {
            isRestoring = true
            // The store keeps its own work going if the view goes away; only the alert is lost.
            Task {
                defer { isRestoring = false }
                do {
                    try await pro.restore()
                    if !pro.status.unlocksEverything { alert = .notFound }
                } catch StoreKitError.userCancelled {
                    // The user cancelled the sign-in.
                } catch {
                    alert = .failed(error.localizedDescription)
                }
            }
        }
        .disabled(isRestoring)
        .proPurchaseAlert($alert)
    }
}

private extension View {
    func proPurchaseAlert(_ alert: Binding<ProPurchaseAlert?>) -> some View {
        // The empty title is never shown: the alert only appears while there is a value.
        self.alert(
            alert.wrappedValue?.title ?? Text(verbatim: ""),
            isPresented: Binding(get: { alert.wrappedValue != nil }, set: { if !$0 { alert.wrappedValue = nil } }),
            presenting: alert.wrappedValue
        ) { _ in
            Button("OK") {}
        } message: { alert in
            alert.message
        }
    }
}

private enum ProPurchaseAlert {
    case pending
    case notFound
    case failed(String)

    var title: Text {
        switch self {
        case .pending: Text("Purchase Pending")
        case .notFound: Text("No Purchase Found")
        case .failed: Text("Purchase Failed")
        }
    }

    var message: Text {
        switch self {
        case .pending: Text("SlidePilot Pro unlocks as soon as the purchase is approved.")
        case .notFound: Text("This Apple Account has not bought SlidePilot Pro.")
        case .failed(let message): Text(message)
        }
    }
}

/// The trial hint's line: "Trial Version – … Unlock Pro". One standard button, so it is a
/// single VoiceOver element and keyboard focus target; no custom chrome around it.
private struct TrialHintButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Trial Version – Presenting and remote limited to 3 minutes. \(Text("Unlock Pro").foregroundStyle(.tint))", comment: "Trial hint at the top of the presenter; the argument is the link-styled \"Unlock Pro\".")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: Self.minimumHeight)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Shows the offer of SlidePilot Pro."))
    }

    // The minimum touch target on iPad and iPhone; the Mac clicks the text itself.
    #if os(iOS)
    private static let minimumHeight: CGFloat? = 44
    #else
    private static let minimumHeight: CGFloat? = nil
    #endif
}

private struct TrialHintModifier: ViewModifier {
    @Environment(ProStore.self) private var pro
    @Environment(\.presenterMakesRoomForDrawing) private var makesRoomForDrawing
    @State private var showsOffer = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top) {
                // Stays while the offer is open, so it shows the purchase instead of vanishing
                // under it; drawing keeps the room for the slide (#152).
                if (pro.status.showsTrialHint || showsOffer) && !makesRoomForDrawing {
                    TrialHintButton { showsOffer = true }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                }
            }
            .proOffer(isPresented: $showsOffer)
    }
}

#if os(iOS)
/// The trial hint on the document browser's launch screen (iPad, iPhone). The launch screen's
/// accessory views take no taps, so the line is information only and "Unlock Pro" is the
/// launch screen's own primary action next to Control Another Device… (a viewer app has no
/// Create Document). SwiftUI's launch scene has no API for that slot, so it is set on UIKit's
/// launch options; the offer is presented from UIKit too, like remote mode.
struct LibraryTrialHint: View {
    @Environment(ProStore.self) private var pro

    var body: some View {
        VStack {
            if pro.status.showsTrialHint {
                Text("Trial Version – Presenting and remote limited to 3 minutes.", comment: "Trial hint at the top of the document browser; the Unlock Pro button is below the app name.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            LaunchPrimaryAction(isShown: pro.status.showsTrialHint) {
                presentOffer()
            }
        }
        // The accessory lies over the launch screen's buttons; it must not take their taps.
        .allowsHitTesting(false)
    }

    private func presentOffer() {
        guard let presenter = LaunchScreenPresenter.topViewController() else { return }
        let host = UIHostingController<PresentedProOffer?>(rootView: nil)
        host.rootView = PresentedProOffer(pro: pro) { [weak host] in
            host?.dismiss(animated: true)
        }
        host.modalPresentationStyle = .formSheet
        presenter.present(host, animated: true)
    }
}

/// Puts "Unlock Pro" into the launch screen's primary action while `isShown`, and removes it
/// again (e.g. after the purchase).
private struct LaunchPrimaryAction: UIViewRepresentable {
    let isShown: Bool
    let perform: () -> Void

    func makeUIView(context: Context) -> InstallerView {
        let view = InstallerView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: InstallerView, context: Context) {
        view.perform = perform
        view.isShown = isShown
    }

    final class InstallerView: UIView {
        var perform: () -> Void = {}
        var isShown = false {
            didSet { if isShown != oldValue { install() } }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            install()
        }

        private func install() {
            guard window != nil else { return }
            // The launch screen belongs to the document view controller up the responder chain.
            var responder = next
            while let current = responder, !(current is UIDocumentViewController) { responder = current.next }
            guard let documentController = responder as? UIDocumentViewController else { return }
            // Captures the closure, not this view, so the action works even if SwiftUI replaces it.
            let perform = perform
            documentController.launchOptions.primaryAction = isShown
                ? UIAction(title: String(localized: "Unlock Pro")) { _ in perform() }
                : nil
        }
    }
}

private struct PresentedProOffer: View {
    let pro: ProStore
    let close: () -> Void

    var body: some View {
        ProOfferView(reason: nil, close: close)
            .environment(pro)
    }
}
#endif

/// The Pro section of Settings: the offer, or that Pro is unlocked, and Restore Purchases.
struct ProSettingsSection: View {
    var body: some View {
        ProProductSection(style: .compact) {
            Text("SlidePilot Pro")
        } extra: {
            RestorePurchasesButton()
        }
    }
}

#else

// The free Mac download: no trial, no hint and no offer (ADR 0020).

private struct ProOfferModifier: ViewModifier {
    @Binding var isPresented: Bool
    let reason: ProOfferReason?

    func body(content: Content) -> some View { content }
}

private struct TrialHintModifier: ViewModifier {
    func body(content: Content) -> some View { content }
}

struct ProSettingsSection: View {
    var body: some View { EmptyView() }
}

#endif
