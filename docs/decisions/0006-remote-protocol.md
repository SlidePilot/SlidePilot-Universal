# 0006 – New remote protocol, shipping in 1.1

- Status: Accepted
- Date: 2026-11-10

## Context
The old remote used MultipeerConnectivity with a 4-digit code confirmed only on the Mac. It accepted commands from unverified devices (parity doc DEF-04). The iPhone app "SlidePilot Remote" lives in a separate repository.

## Decision
- New protocol on the Network framework: Bonjour discovery, encrypted connection keyed from the pairing, Codable messages defined in `SlidePilotRemoteProtocol` with an explicit protocol version.
- The iPhone remote app is rewritten later in this repository.
- Version **1.0 ships without remote**; remote comes with **1.1**.

## Consequences
- The existing SlidePilot Remote app (App Store id 1535769714) does not work with the new app. Users of the old remote lose remote control until 1.1.
- The app will need `NSLocalNetworkUsageDescription`, `NSBonjourServices` and the network client/server entitlements from 1.1 on.
