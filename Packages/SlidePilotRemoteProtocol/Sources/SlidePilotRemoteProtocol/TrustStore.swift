import Foundation
import Synchronization

/// A device this instance paired with (REM-02, REM-03). Trust is per device pair and counts
/// in both directions: either device may control the other (ADR 0015).
public struct TrustedDevice: Sendable, Hashable, Identifiable, Codable {
    public let instanceID: InstanceID
    /// The name the device sent in its `hello` when it paired or last connected.
    public var deviceName: String
    public var pairedAt: Date

    public var id: InstanceID { instanceID }

    public init(instanceID: InstanceID, deviceName: String, pairedAt: Date) {
        self.instanceID = instanceID
        self.deviceName = deviceName
        self.pairedAt = pairedAt
    }
}

/// Where pairing keys are kept between launches.
///
/// Calls are synchronous, because `RemoteConnection` looks keys up inside `receive(_:)`.
/// Implementations must be safe to call from any isolation domain.
public protocol TrustStore: Sendable {
    func key(for instanceID: InstanceID) -> PairingKey?
    /// All trusted devices, sorted by name.
    func devices() -> [TrustedDevice]
    /// Stores or replaces the key of a device.
    func trust(_ device: TrustedDevice, key: PairingKey) throws
    /// Forgets a device and its key. Removing an unknown device is not an error.
    func removeTrust(for instanceID: InstanceID) throws
}

extension Array where Element == TrustedDevice {
    func sortedByName() -> [TrustedDevice] {
        sorted {
            let order = $0.deviceName.localizedStandardCompare($1.deviceName)
            return order == .orderedSame ? $0.instanceID.description < $1.instanceID.description : order == .orderedAscending
        }
    }
}

/// Keeps trust in memory only; for tests and previews.
public final class InMemoryTrustStore: TrustStore {
    private let entries = Mutex<[InstanceID: (device: TrustedDevice, key: PairingKey)]>([:])

    public init() {}

    public func key(for instanceID: InstanceID) -> PairingKey? {
        entries.withLock { $0[instanceID]?.key }
    }

    public func devices() -> [TrustedDevice] {
        entries.withLock { $0.values.map(\.device) }.sortedByName()
    }

    public func trust(_ device: TrustedDevice, key: PairingKey) throws {
        entries.withLock { $0[device.instanceID] = (device, key) }
    }

    public func removeTrust(for instanceID: InstanceID) throws {
        _ = entries.withLock { $0.removeValue(forKey: instanceID) }
    }
}
