# 0015 – iPhone support and remote as a mode of the app, both in 2.0

- Status: Accepted (pricing: [0020](0020-free-app-with-pro-purchase.md))
- Date: 2026-11-16
- Partially supersedes: [0001](0001-minimum-os.md) (iPhone is a target), [0006](0006-remote-protocol.md) (remote ships with 2.0, no separate remote app, symmetric roles)

## Context
ADR 0001 kept the iPhone out of the main app, and ADR 0006 planned a separate iPhone remote app in this repository for 2.1. The app target is already multiplatform; only `TARGETED_DEVICE_FAMILY = 2` limits it to the iPad. The remote protocol is not implemented yet.

A single app on iPhone, iPad and Mac can do both jobs: present a PDF, and remote-control another SlidePilot instance. This also gives combinations the old remote could not offer, for example an iPad controlling a Mac.

Apple's foldable iPhone Duo (iOS 27, October 2026) runs iPhone apps on two displays: the outer display behaves like other iPhones (compact width), and the inner display gives the app a regular width like an iPad, with several windows and Split View. Apps keep their process and scene when the device is folded, unfolded or flipped; they only get size class and trait changes. Apps built with the iOS 26 SDK are shown centered with empty space around them on the inner display; the iOS 27 SDK resizes them dynamically, and the iOS 27.1 SDK fills the inner display edge to edge and moves toolbars to vertical bars below the status bar. See [Apple's guide](https://developer.apple.com/iphone-duo/prepare/) and the [HIG page](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo).

## Decision
**iPhone in 2.0**
- The iPhone work is done together at the end of Phase 4, after the remote and before Phase 5 (Polish & Release). Until then, new UI only follows the layout rules below, so nothing has to be rebuilt later.
- The app supports the iPhone from **2.0** on (`TARGETED_DEVICE_FAMILY = 1,2`), with iOS 26.0 as deployment target like the iPad. On iPhone it has the same features as on the iPad: open, present (external display by cable or AirPlay), notes, pointer, drawing.
- The iPhone uses the iPad's platform notes in `docs/feature-parity.md` unless an item says otherwise.
- **iPhone Duo is supported** on both displays: the outer display with the compact layout, the inner display with the regular layout and several windows, like the iPad.
- Layouts adapt to the available size and size classes, never to the device idiom (`userInterfaceIdiom`), the orientation or fixed screen sizes. `UIScreen.main` is not used. Folding, unfolding and flipping keep the presentation state, including a running presentation on the external display.
- Toolbars and bars are standard SwiftUI components (ADR 0010), so they follow the iPhone Duo's vertical bars without custom code.
- Release builds use **Xcode 27.1 or later** (iOS 27.1 SDK), so the app is optimized for the iPhone Duo. The deployment target stays 26.0; APIs newer than iOS 26 need availability checks.
- Memory limits (ADR 0005) are chosen per device class, not per platform; the iPhone budget is measured on a device like the iPad budget.

**Remote as a mode of the app (2.0)**
- There is **no separate remote app**. Every SlidePilot instance on iPhone, iPad and Mac can control another instance (remote mode) and can be controlled (as presenter).
- The protocol (ADR 0006) is symmetric: an instance offers its open presentations; a controller lists the devices and their presentations and picks one. An instance never controls itself.
- Pairing and trust work the same in both directions; trust is stored per device pair in the Keychain.
- The remote ships with **2.0**, not 2.1 as ADR 0006 planned.

**Pricing**
- Unchanged (ADR 0011): one paid universal app record. The iPhone joins the existing iOS platform of that record.

## Consequences
- iPhone support cannot be removed from the App Store record once a build supporting it has been released.
- App Store Connect needs iPhone screenshots; iPhone Duo screenshots are optional and earn the "optimized for iPhone Duo" badge.
- The Xcode Cloud workflow must archive with Xcode 27.1 or later. CI moves from Xcode 26.6 to Xcode 27.1 (with an iPhone simulator job) as soon as the GitHub runner image provides it; until then, the iPhone Duo inner display can only be checked locally.
- UI work covers compact width as a regular case. The Definition of Done (CLAUDE.md) gets iPhone screenshots and checks in the PR that enables the iPhone target.
- Users of the free Mac download (ADR 0011) buy the App Store app to control their Mac from an iPhone or iPad. The old SlidePilot Remote app is not updated (ADR 0006); since the remote ships with 2.0, its users have no gap without remote control.
- The app needs `NSLocalNetworkUsageDescription`, `NSBonjourServices` and the network entitlements from 2.0 on.
- Open questions, answered by issues before 2.0: the external display behavior on iPhone and iPhone Duo (USB-C and AirPlay) and the iPhone memory budget.
- Parity items REM-01 and REM-07 change from "iPhone remote app" to "remote mode in every instance".
