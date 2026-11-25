# 0020 – Free App Store app with the in-app purchase SlidePilot Pro

- Status: Accepted
- Date: 2026-11-25
- Partially supersedes: [0011](0011-universal-purchase-and-direct-download.md) (the paid universal app record), [0015](0015-iphone-and-remote-mode.md) (section "Pricing")

## Context
ADR 0011 made the App Store version one paid universal app for macOS and iPadOS; ADR 0015 added the iPhone to the same record at the same price. A paid download asks for money before anyone has seen the app, and presenters usually want to check the external display, AirPlay or the remote in their own setup before they pay. The app has only been in TestFlight so far, so nobody has bought it yet and no earlier purchase has to be honored.

A free download with an in-app purchase keeps the record structure of ADR 0011: one universal record, one bundle ID. Only the price and an in-app purchase change, and both can be changed later without a new record.

## Decision
**Price**
- The App Store record (one universal app for macOS, iPadOS and iPhone) is **free**.
- The full scope is unlocked by one **non-consumable in-app purchase "SlidePilot Pro"** (StoreKit 2), **7.99 EUR** (the matching price tier in other storefronts). One purchase unlocks Pro on every platform of the universal app. **Family Sharing** is on.
- The same rules apply on Mac, iPad and iPhone (App Store build).

**Unlimited without Pro**: everything that happens only on the user's own device: opening documents, the presenter view, notes, timer, pointer, drawing, curtain, settings.

**Trial without Pro**: everything the audience sees or that connects devices:
- Audience output: an external display or AirPlay on iPad and iPhone; on the Mac **every presentation window**, on a second screen or on the presenter's screen in its own Space. A single-screen Mac can mirror its screen to a projector, so the window counts as audience output wherever it is.
- The pointer, the drawing and the black or white curtain on that output (they are part of it).
- Remote control in both directions: controlling another device and being controlled.

**Trial**
- At most **3 minutes** per session. A session is one audience output (from connecting the display, or on the Mac from opening the presentation window) or one remote connection.
- During the trial the audience screen shows a permanent banner "SlidePilot – Trial Version".
- When the time is up, the output stops showing the deck and the remote connection closes. The device shows "Trial Ended" with the purchase offer.
- A new trial starts only after connecting again: reconnecting the display, starting the presentation again on the Mac, or connecting the remote again. Automatic reconnects (for example of trusted remote devices) do not start a new trial.
- Buying Pro during a trial lifts the limit and removes the banner at once.
- Each App Store installation checks only its own Pro status. Nothing about it is sent over the remote protocol (ADR 0017 stays unchanged). A remote connection is therefore a trial on every App Store installation without Pro that takes part, also when the other side is the free Mac download or has Pro.

**Hint and purchase offer**
- While Pro is missing, a subtle native hint sits at the top of the library and of the presenter view: "Trial Version – Presenting and remote limited to 3 minutes. Unlock Pro". It opens the purchase offer and disappears after the purchase.
- The purchase offer uses StoreKit's own views (`ProductView` or `StoreView`, ADR 0010). It appears when an external display connects or a presentation window opens, when remote mode starts or this device is first controlled, at the end of a trial, and in Settings. Settings also has "Restore Purchases".

**Free Mac download** (build configuration `FreeDownload`, ADR 0011)
- No limit at all: no trial, no hint, no purchase offer and no StoreKit code. The compile-time flag `SLIDEPILOT_FREE_DOWNLOAD` that already controls the donation hint excludes it.
- The rest of ADR 0011 stays valid: free download on the website and GitHub Releases, donation hint only there, the App Store version and its listing do not mention it.

## Consequences
- The rules (Pro status, which features are limited, the trial timer) are value types and a small state model in SlidePilotCore and are tested there without StoreKit. StoreKit 2 lives only in the app target, behind the flag.
- The product ID is a build setting in `Config/Shared.xcconfig` (derived from `BUNDLE_ID_PREFIX`) and reaches the code through the Info.plist; no Swift file hard-codes it. A StoreKit configuration file in the repository lets the scheme test purchases locally without App Store Connect.
- App Store Connect needs the in-app purchase with a review screenshot, the free price and the Paid Apps agreement (see `docs/release.md`). The first version with the purchase must submit it together with the app version.
- Users of the free Mac download keep everything. To control their Mac from an iPhone or iPad they now install the free App Store app and buy Pro there (replaces that sentence of ADR 0015).
- Two App Store installations of the same user share Pro through the same Apple Account (and Family Sharing); an installation signed in with another account without Pro stays a trial on its side of a remote connection.
- A rehearsal with the Mac presentation window on a single screen is also limited to 3 minutes without Pro; the presenter view itself never is.
- If the model changes again (for example a different price or a subscription), only the in-app purchase and this ADR change; the app record stays.
