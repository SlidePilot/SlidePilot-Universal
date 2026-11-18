import SlidePilotRemoteProtocol
import SwiftUI

/// The Remote pane (REM-02, REM-03): remote control on/off, nearby devices with Connect and
/// Disconnect, the pairing code alert and the trusted devices.
///
/// Browsing runs and pairing requests are accepted only while the pane is visible.
struct RemoteSettingsPane: View {
    @Environment(RemoteService.self) private var remote
    @State private var isShowingTrustedDevices = false

    var body: some View {
        content
            .task { await remote.browse() }
            .alert(
                pairingTitle,
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
            .sheet(isPresented: $isShowingTrustedDevices) {
                TrustedDevicesView()
            }
    }

    @ViewBuilder private var content: some View {
        #if os(macOS)
        SettingsPane { sections }
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
                Text("No devices found")
                    .foregroundStyle(.secondary)
            }
            ForEach(remote.devices) { device in
                RemoteDeviceRow(device: device)
            }
        } header: {
            Text("Nearby Devices")
        } footer: {
            Text("Open SlidePilot on another device on the same network and open Settings ▸ Remote there too. Then connect and check that both devices show the same code.")
        }
        Section {
            Button("Trusted Devices…") {
                isShowingTrustedDevices = true
            }
        }
    }

    private var pairingTitle: Text {
        Text("Pair with “\(remote.pairingRequests.first?.deviceName ?? "")”?")
    }

    private var problemTitle: Text {
        guard let problem = remote.problem else { return Text(verbatim: "") }
        return switch problem.kind {
        case .declined: Text("“\(problem.deviceName)” did not pair")
        case .incompatibleVersion: Text("Can’t connect to “\(problem.deviceName)”")
        case .notVerified: Text("Pairing with “\(problem.deviceName)” failed")
        case .unreachable: Text("Can’t connect to “\(problem.deviceName)”")
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

/// One nearby device with its state and the matching action.
private struct RemoteDeviceRow: View {
    @Environment(RemoteService.self) private var remote
    let device: RemoteService.Device

    var body: some View {
        LabeledContent {
            switch device.status {
            case .available:
                Button("Connect") { remote.pair(with: device.id) }
                    .accessibilityLabel(Text("Connect to \(device.name)"))
            case .pairing:
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(Text("Pairing"))
            case .trusted:
                EmptyView()
            case .connected:
                // Disconnecting also removes the trust, as in the old app (REM-03).
                Button("Disconnect") { remote.disconnect(device.id) }
                    .accessibilityLabel(Text("Disconnect \(device.name)"))
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

/// The trusted devices (REM-03): list and remove.
struct TrustedDevicesView: View {
    @Environment(RemoteService.self) private var remote
    @Environment(\.dismiss) private var dismiss
    @State private var deviceToRemove: TrustedDevice?

    var body: some View {
        NavigationStack {
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
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
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
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 280)
        #endif
    }

    private func row(for device: TrustedDevice) -> some View {
        LabeledContent {
            #if os(macOS)
            Button("Remove") { deviceToRemove = device }
                .accessibilityLabel(Text("Remove \(device.deviceName)"))
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
