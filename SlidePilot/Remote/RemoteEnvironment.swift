import Foundation
import SlidePilotCore
import SlidePilotRemoteProtocol
#if os(iOS)
import UIKit
#endif

extension RemoteService {
    /// The service of the running app: its stored instance ID, the device name and the
    /// Keychain trust store.
    static func live(settings: AppSettings) -> RemoteService {
        RemoteService(settings: settings, identity: liveIdentity(), trustStore: liveTrustStore())
    }

    /// Not a secret (it is in the Bonjour TXT record), so user defaults are fine.
    private static let instanceIDKey = "remoteInstanceID"

    private static func liveIdentity() -> LocalIdentity {
        let defaults = UserDefaults.standard
        let instanceID: InstanceID
        if let stored = defaults.string(forKey: instanceIDKey).flatMap(InstanceID.init(string:)) {
            instanceID = stored
        } else {
            instanceID = InstanceID()
            defaults.set(instanceID.description, forKey: instanceIDKey)
        }
        return LocalIdentity(instanceID: instanceID, deviceName: deviceName)
    }

    private static var deviceName: String {
        if isTestHostBuild {
            // Screenshots of the test build must not show the real computer name.
            return "SlidePilot Test Mac"
        }
        #if os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return UIDevice.current.name
        #endif
    }

    private static func liveTrustStore() -> any TrustStore {
        if isTestHostBuild {
            // The test build is rebuilt and re-signed often; Keychain items of an earlier
            // build would ask for access. Its trust lasts until it quits.
            return InMemoryTrustStore()
        }
        // Derived from the bundle ID, so builds with other IDs keep their own trust.
        return KeychainTrustStore(service: "\(Bundle.main.bundleIdentifier ?? "SlidePilot").remote-trust")
    }

    private static var isTestHostBuild: Bool {
        #if DEBUG
        Bundle.main.bundleIdentifier?.hasSuffix(".testhost") == true
        #else
        false
        #endif
    }
}
