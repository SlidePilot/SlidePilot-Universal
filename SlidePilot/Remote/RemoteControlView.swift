import SlidePilotCore
import SlidePilotRemoteProtocol
import SwiftUI

/// The remote mode scene (REM-07, ADR 0015): one window that controls a presentation on
/// another device. Opened with File ▸ Control Another Device… and, on iPad, from the
/// document browser.
enum RemoteControlScene {
    static let id = "remote-control"
}

/// Opens a remote mode window.
struct ControlAnotherDeviceButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Control Another Device…", systemImage: "appletvremote.gen4") {
            openWindow(id: RemoteControlScene.id)
        }
    }
}

/// File ▸ Control Another Device… (REM-07).
struct RemoteControlCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            ControlAnotherDeviceButton()
        }
    }
}

/// The content of a remote mode window: device list → presentations → slides, in a
/// navigation stack so Back leaves each step; Escape does too on the slides.
struct RemoteControlView: View {
    @Environment(RemoteService.self) private var remote
    @State private var control: RemoteControl?

    var body: some View {
        Group {
            if let control {
                RemoteControlStack(control: control)
            }
        }
        .onAppear {
            if control == nil {
                control = RemoteControl(remote: remote)
            }
        }
        // Nearby devices are found while the window is open. It does not accept pairing
        // requests of other devices; Settings ▸ Remote does that (REM-02).
        .task { await remote.browse(acceptsPairingRequests: false) }
        .remoteAlerts()
    }
}

private struct RemoteControlStack: View {
    @Bindable var control: RemoteControl

    var body: some View {
        NavigationStack(path: Binding(get: { control.route }, set: { control.navigate(to: $0) })) {
            RemoteDeviceList(control: control)
                .navigationDestination(for: RemoteControl.Route.self) { route in
                    switch route {
                    case .presentations: RemotePresentationList(control: control)
                    case .slides: RemoteSlidesView(control: control)
                    }
                }
        }
        // Cancelled when the window closes, so the connection never outlives it.
        .task(id: control.connectionID) { await control.keepConnected() }
        .alert(
            endingTitle,
            isPresented: Binding(get: { control.ending != nil }, set: { if !$0 { control.ending = nil } }),
            presenting: control.ending
        ) { _ in
            Button("OK") {}
        } message: { ending in
            switch ending {
            case .trustRemoved(let name):
                Text("“\(name)” removed this device from its trusted devices. Pair again to control it.")
            case .pairingRequired(let name):
                Text("“\(name)” does not trust this device any more. Select it again to pair.")
            }
        }
    }

    private var endingTitle: Text {
        switch control.ending {
        case .trustRemoved(let name)?, .pairingRequired(let name)?:
            Text("Disconnected from “\(name)”")
        case nil:
            Text(verbatim: "")
        }
    }
}

// MARK: - Devices

private struct RemoteDeviceList: View {
    @Environment(RemoteService.self) private var remote
    @Environment(AppSettings.self) private var settings
    let control: RemoteControl
    /// A window connects on its own only once, so going back to the list stays there.
    @State private var hasTriedLastDevice = false

    var body: some View {
        List {
            Section {
                ForEach(remote.controllableDevices) { device in
                    Button {
                        connect(to: device)
                    } label: {
                        LabeledContent {
                            if control.deviceID == device.id {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        } label: {
                            Text(device.name)
                            if device.status == .available {
                                Text("Not paired")
                            } else {
                                Text("Trusted")
                            }
                        }
                    }
                    // Rows read like list items, not like links.
                    .tint(.primary)
                    .accessibilityHint(Text(device.status == .available ? "Pairs with this device and controls it." : "Controls this device."))
                }
            } header: {
                Text("Nearby Devices")
            } footer: {
                Text("Select a device running SlidePilot on the same network. To pair a new device, open Settings ▸ Remote on it first, then check that both devices show the same code.")
            }
        }
        .overlay {
            if remote.controllableDevices.isEmpty {
                ContentUnavailableView {
                    Label("Searching for Devices", systemImage: "antenna.radiowaves.left.and.right")
                } description: {
                    Text("Open SlidePilot on another device on the same network. “Allow remote control” must be on there.")
                }
            }
        }
        .navigationTitle("Remote Control")
        // Connects again to the device controlled last, once it is found nearby and trusted.
        .onChange(of: remote.controllableDevices, initial: true) { _, devices in
            guard !hasTriedLastDevice, control.deviceID == nil, let last = settings.remoteLastDeviceID,
                  let device = devices.first(where: { $0.id.description == last })
            else { return }
            hasTriedLastDevice = true
            if device.status == .trusted {
                control.connect(to: device)
            }
        }
    }

    private func connect(to device: RemoteService.Device) {
        hasTriedLastDevice = true
        settings.remoteLastDeviceID = device.id.description
        control.connect(to: device)
    }
}

// MARK: - Presentations

private struct RemotePresentationList: View {
    let control: RemoteControl

    var body: some View {
        List {
            if let title = control.state.closedTitle {
                Section {
                    Label("“\(title)” was closed on “\(control.deviceName)”.", systemImage: "xmark.rectangle")
                }
            }
            Section {
                ForEach(control.state.presentations, id: \.id) { presentation in
                    Button {
                        control.select(presentation.id)
                    } label: {
                        LabeledContent {
                            EmptyView()
                        } label: {
                            Text(presentation.title)
                            Text("^[\(presentation.slideCount) slide](inflect: true)")
                        }
                    }
                    .tint(.primary)
                }
            } header: {
                if !control.state.presentations.isEmpty {
                    Text("Open Presentations")
                }
            }
        }
        .overlay {
            if control.connection != .connected {
                ContentUnavailableView {
                    Label {
                        Text(control.connection == .reconnecting ? "Reconnecting…" : "Connecting…")
                    } icon: {
                        ProgressView()
                    }
                } description: {
                    Text("Keep SlidePilot open on “\(control.deviceName)”.")
                }
            } else if control.state.hasPresentations, control.state.presentations.isEmpty {
                ContentUnavailableView(
                    "No Open Presentations",
                    systemImage: "doc.richtext",
                    description: Text("Open a presentation on “\(control.deviceName)”.")
                )
            }
        }
        // Back disconnects and shows the device list again.
        .navigationTitle(control.deviceName)
    }
}
