# 0011 – Universal purchase and free Mac download

- Status: Accepted (signing IDs: [0014](0014-commit-signing-ids.md))
- Date: 2026-11-12
- Supersedes: [0003](0003-app-store-distribution.md)

## Context
ADR 0003 planned a free Mac app and a paid iPad app and deferred the pricing model (one universal purchase vs. two separate App Store apps). Creating the App Store Connect record for the first TestFlight build forces that choice, because the record structure is hard to change later:

- A platform can only be deleted from an app record if no build was ever uploaded for it.
- Once App Store Review approves two platform versions, the app becomes a universal purchase. A single platform can then no longer be removed.
- A bundle ID that had a build uploaded cannot be reused, even if the app record is deleted.

App Store pricing is per app record, not per platform. A free Mac app and a paid iPad app would therefore need two records and two bundle IDs.

## Decision
- **App Store: one universal app record** for iPadOS and macOS, one bundle ID, one price. Buying it on either platform unlocks both.
- **Free Mac download outside the App Store:** the Mac app is also offered for free on the website and GitHub Releases, signed with Developer ID and notarized. It has no update mechanism; a minimal "new version available" check (without third-party dependencies) may be added later.
- **Donation hint:** none in the App Store version. The free download shows a simple donation hint. App Store rules do not apply to it.
- The App Store version and its listing do not mention the free download.
- Sparkle is not used. Both builds are sandboxed.

## Consequences
- Bundle ID, team and product flags stay in xcconfig files; nothing hard-codes a bundle ID. The real bundle ID prefix and team stay in the git-ignored `Config/Local.xcconfig`.
- The free download is a second build variant of the same target (own xcconfig/scheme, own bundle ID so it does not share settings or the sandbox container with the App Store version). It is planned as a separate issue.
- The donation hint is behind a compile-time flag that only the free download sets.
- If the pricing model has to change later, the iPad app must move to a new bundle ID and a new record. The iOS platform then stays unused in the existing record.
