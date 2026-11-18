import SlidePilotRemoteProtocol
import SwiftUI

/// The Remote pane (REM-02, REM-03): remote control on/off, nearby devices with Connect and
/// Disconnect, and the trusted devices.
///
/// Browsing runs and pairing requests are accepted only while the pane is visible. The
/// pairing code and problem alerts come from `remoteAlerts()`: on the Mac on the pane and
/// the Trusted Devices sheet, on iPad on the settings sheet's navigation stack, so they show
/// wherever the user is in Settings.
struct RemoteSettingsPane: View {
    @Environment(RemoteService.self) private var remote
    @State private var isShowingTrustedDevices = false
    @State private var deviceToDisconnect: RemoteService.Device?

    var body: some View {
        content
            .task { await remote.browse() }
            .alert(
                Text("Disconnect “\(deviceToDisconnect?.name ?? "")”?"),
                isPresented: Binding(
                    get: { deviceToDisconnect != nil },
                    set: { if !$0 { deviceToDisconnect = nil } }
                ),
                presenting: deviceToDisconnect
            ) { device in
                Button("Disconnect", role: .destructive) { remote.disconnect(device.id) }
                Button("Cancel", role: .cancel) {}
            } message: { device in
                Text("“\(device.name)” is also removed from the trusted devices and has to be paired again.")
            }
    }

    @ViewBuilder private var content: some View {
        #if os(macOS)
        SettingsPane { sections }
            .remoteAlerts()
            .sheet(isPresented: $isShowingTrustedDevices) {
                NavigationStack {
                    TrustedDevicesList()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { isShowingTrustedDevices = false }
                            }
                        }
                }
                .frame(minWidth: 380, minHeight: 280)
                .onExitCommand { isShowingTrustedDevices = false }
                .remoteAlerts()
            }
        #else
        Form { sections }
            .navigationTitle("Remote")
        #endif
    }

    @ViewBuilder private var sections: some View {
        @Bindable var remote = remote
        Section {
            Toggle(isOn: $remote.allowsRemoteControl) {
                Text("Allow remote control")
                Text("Paired devices can find this device and control its presentations.")
            }
        }
        Section {
            if remote.devices.isEmpty {
                Label {
                    Text("Searching for devices…")
                } icon: {
                    ProgressView()
                        .controlSize(.small)
                }
                .foregroundStyle(.secondary)
            }
            ForEach(remote.devices) { device in
                RemoteDeviceRow(device: device) {
                    deviceToDisconnect = device
                }
            }
        } header: {
            Text("Nearby Devices")
        } footer: {
            Text("Open SlidePilot on another device on the same network and open Settings ▸ Remote there too. Then connect and check that both devices show the same code.")
        }
        Section {
            #if os(macOS)
            Button("Trusted Devices…") {
                isShowingTrustedDevices = true
            }
            #else
            NavigationLink("Trusted Devices") {
                TrustedDevicesList()
            }
            #endif
        }
    }
}

/// One nearby device with its state and the matching action.
private struct RemoteDeviceRow: View {
    @Environment(RemoteService.self) private var remote
    let device: RemoteService.Device
    let disconnect: () -> Void

    var body: some View {
        LabeledContent {
            switch device.status {
            case .available, .trusted:
                // On a trusted device this checks the trust and pairs again if the other
                // device forgot this one.
                Button("Connect") { remote.pair(with: device.id) }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Connect to \(device.name)"))
                    .accessibilityInputLabels([Text("Connect"), Text("Connect to \(device.name)")])
            case .pairing:
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            case .connected:
                // Disconnecting also removes the trust, as in the old app (REM-03).
                Button("Disconnect", action: disconnect)
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Disconnect \(device.name)"))
                    .accessibilityInputLabels([Text("Disconnect"), Text("Disconnect \(device.name)")])
            }
        } label: {
            Text(device.name)
            switch device.status {
            case .available: EmptyView()
            case .pairing: Text("Pairing…")
            case .trusted: Text("Trusted")
            case .connected: Text("Connected")
            }
        }
    }
}

/// The trusted devices (REM-03): list and remove, each after a confirmation as in the old app.
struct TrustedDevicesList: View {
    @Environment(RemoteService.self) private var remote
    @State private var deviceToRemove: TrustedDevice?

    var body: some View {
        List {
            ForEach(remote.trustedDevices) { device in
                row(for: device)
            }
            .onDelete { offsets in
                deviceToRemove = offsets.first.map { remote.trustedDevices[$0] }
            }
        }
        .overlay {
            if remote.trustedDevices.isEmpty {
                ContentUnavailableView(
                    "No Trusted Devices",
                    systemImage: "lock.shield",
                    description: Text("Devices you pair with appear here.")
                )
            }
        }
        .navigationTitle("Trusted Devices")
        #if os(iOS)
        .toolbar {
            if !remote.trustedDevices.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
        }
        #endif
        .alert(
            Text("Remove “\(deviceToRemove?.deviceName ?? "")”?"),
            isPresented: Binding(
                get: { deviceToRemove != nil },
                set: { if !$0 { deviceToRemove = nil } }
            ),
            presenting: deviceToRemove
        ) { device in
            Button("Remove", role: .destructive) { remote.removeTrust(for: device.instanceID) }
            Button("Cancel", role: .cancel) {}
        } message: { device in
            Text("“\(device.deviceName)” has to be paired again before either device can control the other.")
        }
    }

    private func row(for device: TrustedDevice) -> some View {
        LabeledContent {
            #if os(macOS)
            Button("Remove") { deviceToRemove = device }
                .accessibilityLabel(Text("Remove \(device.deviceName)"))
                .accessibilityInputLabels([Text("Remove"), Text("Remove \(device.deviceName)")])
            #endif
        } label: {
            Text(device.deviceName)
            Text("Paired \(device.pairedAt, format: .dateTime.day().month().year())")
        }
        .contextMenu {
            Button("Remove", systemImage: "trash", role: .destructive) { deviceToRemove = device }
        }
    }
}

extension View {
    /// The pairing code and pairing problem alerts of the remote (REM-02).
    func remoteAlerts() -> some View {
        modifier(RemoteAlertsModifier())
    }
}

private struct RemoteAlertsModifier: ViewModifier {
    @Environment(RemoteService.self) private var remote

    func body(content: Content) -> some View {
        content
            .alert(
                Text("Pair with “\(remote.pairingRequests.first?.deviceName ?? "")”?"),
                isPresented: Binding(
                    get: { remote.pairingRequests.first != nil },
                    set: { _ in }
                ),
                presenting: remote.pairingRequests.first
            ) { request in
                Button("Pair") { remote.confirm(request) }
                    .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) { remote.reject(request) }
            } message: { request in
                Text("Code: \(request.formattedCode)\n\nPair only if “\(request.deviceName)” shows the same code.")
            }
            .alert(
                problemTitle,
                isPresented: Binding(
                    get: { remote.problem != nil },
                    set: { if !$0 { remote.problem = nil } }
                ),
                presenting: remote.problem
            ) { _ in
                Button("OK") {}
            } message: { problem in
                Text(Self.message(for: problem))
            }
    }

    private var problemTitle: Text {
        guard let problem = remote.problem else { return Text(verbatim: "") }
        return switch problem.kind {
        case .declined: Text("Pairing with “\(problem.deviceName)” Cancelled")
        case .incompatibleVersion, .unreachable: Text("Can’t Connect to “\(problem.deviceName)”")
        case .notVerified: Text("Pairing with “\(problem.deviceName)” Failed")
        }
    }

    private static func message(for problem: RemoteService.Problem) -> String {
        switch problem.kind {
        case .declined:
            String(localized: "The pairing was cancelled. To pair, open Settings ▸ Remote on both devices and confirm the code on both.")
        case .incompatibleVersion(let peerNeedsUpdate):
            peerNeedsUpdate
                ? String(localized: "Update SlidePilot on “\(problem.deviceName)” to the latest version.")
                : String(localized: "Update SlidePilot on this device to the latest version.")
        case .notVerified:
            String(localized: "The devices could not verify each other. Try again.")
        case .unreachable:
            String(localized: "Check that both devices are on the same network and SlidePilot is open on “\(problem.deviceName)”.")
        }
    }
}
