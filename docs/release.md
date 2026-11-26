# Release and TestFlight

SlidePilot ships as one universal App Store app for macOS, iPadOS and iPhone (ADR 0011, 0015). One App Store Connect record holds both platforms; each platform gets its own archive and upload. The app is free; the in-app purchase SlidePilot Pro unlocks unlimited presenting and remote control (ADR 0020).

## One-time setup (product owner)
- The App Store Connect record exists with the platforms iOS and macOS and the same bundle ID as the app.
- `Config/Shared.xcconfig` sets `BUNDLE_ID_PREFIX` and `DEVELOPMENT_TEAM` so that `$(BUNDLE_ID_PREFIX).SlidePilot` matches the record's bundle ID (ADR 0014).
- Xcode is signed in to the developer account (Xcode ▸ Settings ▸ Apple Accounts). Automatic signing creates the distribution certificate and profiles on the first signed archive (`-allowProvisioningUpdates`).
- The current Apple Developer Program License Agreement is accepted in App Store Connect.

## Price and in-app purchase (product owner, ADR 0020)
1. **Agreements:** in App Store Connect ▸ Business, the Paid Apps agreement is active, with bank account and tax forms complete. Without it, in-app purchases cannot be sold or tested in the sandbox outside Xcode.
2. **Price:** App ▸ Pricing and Availability ▸ price **Free** (0.00) in every storefront.
3. **In-app purchase:** App ▸ Monetization ▸ In-App Purchases ▸ create a **Non-Consumable**:
   - Reference name "SlidePilot Pro", product ID `<bundle ID>.pro`, i.e. the value of `SLIDEPILOT_PRO_PRODUCT_ID` in `Config/Shared.xcconfig` (set up in #198).
   - Price **7.99 EUR** (base storefront Germany; App Store Connect fills the other storefronts).
   - **Family Sharing** on (it cannot be turned off again once on).
   - Display name "SlidePilot Pro" in en, de and fr. Description (at most 45 characters): en "Unlimited presenting and remote control", de "Unbegrenzt präsentieren und fernsteuern", fr "Présentation et télécommande illimitées".
   - Review information: a **screenshot of the purchase offer** in the app (from the PR of #201) and a review note saying where the offer appears (Settings ▸ SlidePilot Pro).
4. **Submission:** the first in-app purchase must be added to the app version (Version ▸ In-App Purchases and Subscriptions) and is reviewed together with it.
5. **Testing before release:** locally with the StoreKit configuration file `Config/SlidePilot.storekit` of the `SlidePilot` scheme, run from Xcode (no App Store Connect needed; Debug ▸ StoreKit ▸ Manage Transactions refunds or deletes test purchases); in TestFlight the purchase uses the sandbox and costs nothing.

## Versions and build numbers
- `MARKETING_VERSION` in `Config/Shared.xcconfig` is the user-visible version.
- `CURRENT_PROJECT_VERSION` stays `1` in the repository. On upload, Xcode raises the build number to the next free one for that version and platform (`manageAppVersionAndBuildNumber` in `Config/ExportOptions-AppStore.plist`), so no commit is needed per upload.

## Before each release
- Run the workflow **iOS tests** on `main` (GitHub ▸ Actions ▸ iOS tests ▸ Run workflow) and wait until it is green. Pull requests only build iOS, so this is the run of the tests in the iPad simulator (ADR 0008). A failed run opens an issue "iOS tests fail in the iPad simulator"; fix it before archiving.
- The latest CI run on `main` is green (it also builds the free download, the Mac snapshots and the test host).

## Archive and upload with Xcode Cloud (default)
The Xcode Cloud workflow "Default" archives the `SlidePilot` scheme for macOS and iOS and uploads both builds to App Store Connect (distribution preparation "App Store Connect", no post-actions).

- It only starts manually: in App Store Connect (Xcode Cloud ▸ Builds ▸ Start Build) or in Xcode (Report navigator ▸ Cloud ▸ right-click the workflow ▸ Start Build). Choose the branch, usually `main`.
- Xcode Cloud sets the build number itself and counts up per build.
- One release run uses roughly 20–40 compute minutes of the 25 free hours per month. Usage is shown in App Store Connect under Xcode Cloud ▸ Usage. When the hours are used up, builds stop until the next month; nothing is charged.
- `SlidePilot.xcodeproj/xcshareddata/xcodecloud/manifest.json` links the project to the Xcode Cloud product. The workflow itself lives in App Store Connect.

## Archive and upload manually (fallback)
Run from the repository root, once per platform. `./build/` is git-ignored. Xcode picks the next free build number on upload, so manual uploads do not collide with Xcode Cloud builds.

```sh
# macOS
xcodebuild -project SlidePilot.xcodeproj -scheme SlidePilot -configuration Release -destination 'generic/platform=macOS' -archivePath ./build/SlidePilot-macOS.xcarchive -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath ./build/SlidePilot-macOS.xcarchive -exportOptionsPlist Config/ExportOptions-AppStore.plist -exportPath ./build/export-macOS -allowProvisioningUpdates

# iPadOS
xcodebuild -project SlidePilot.xcodeproj -scheme SlidePilot -configuration Release -destination 'generic/platform=iOS' -archivePath ./build/SlidePilot-iOS.xcarchive -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath ./build/SlidePilot-iOS.xcarchive -exportOptionsPlist Config/ExportOptions-AppStore.plist -exportPath ./build/export-iOS -allowProvisioningUpdates
```

Remove an old archive first (`rm -rf ./build/SlidePilot-macOS.xcarchive`) if one exists. Alternatively, archive in Xcode (Product ▸ Archive) and use Distribute App ▸ TestFlight & App Store in the Organizer.

After the upload, App Store Connect processes the build (usually 10–30 minutes). Then add it to an internal TestFlight group.

## Free Mac download (outside the App Store)
The free download (ADR 0011) is the build configuration `FreeDownload` of the same target, built with the scheme `SlidePilot Free Download`. `Config/FreeDownload.xcconfig` gives it its own bundle ID (`$(BUNDLE_ID_PREFIX).SlidePilot.FreeDownload`), limits it to macOS and sets the flag `SLIDEPILOT_FREE_DOWNLOAD`, which turns on the donation hint (DROP-03) and compiles out StoreKit and the SlidePilot Pro trial (ADR 0020), so everything is unlimited. It has no update mechanism.

### Release with the script (default)
Run this in a terminal from the repository root, on `main` after the release's version bump is merged:

```sh
git pull origin main --ff-only
scripts/release-free-download.sh
```

The script reads `MARKETING_VERSION`, archives the scheme, exports it with Developer ID, waits for Apple's notarization (usually a few minutes, at most about 30), checks signature, stapled ticket and Gatekeeper, and zips the app as `SlidePilot-<version>-macOS.zip` (for example `SlidePilot-2.0-macOS.zip`) in `./build/release-free-download/`. It then creates a **draft** GitHub release `v<version>` (for example `v2.0`) at the current commit, with notes generated from the merged pull requests and the zip's SHA-256. Review the notes on GitHub and publish the release there.

- `--publish` publishes the release right away instead of as a draft.
- `--no-release` only builds and checks the zip (for example to test it before tagging).
- It stops before building if the working tree is not clean, `main` differs from `origin/main`, `gh` is not signed in, or the tag or release already exists.
- It needs the Developer ID signing of the Xcode account, the network and `gh`, so it cannot run inside the Claude Code sandbox.

### Manual steps (fallback)

```sh
xcodebuild -project SlidePilot.xcodeproj -scheme "SlidePilot Free Download" -destination 'generic/platform=macOS' -archivePath ./build/SlidePilot-FreeDownload.xcarchive -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath ./build/SlidePilot-FreeDownload.xcarchive -exportOptionsPlist Config/ExportOptions-DeveloperID.plist -exportPath ./build/export-FreeDownload -allowProvisioningUpdates
```

With `destination` `upload`, the export signs with Developer ID and sends the app to Apple's notary service. Once Apple has notarized it, `xcodebuild -exportNotarizedApp -archivePath ./build/SlidePilot-FreeDownload.xcarchive -exportPath ./build/notarized-FreeDownload` writes the stapled app. Alternatively, archive the scheme in Xcode and use Distribute App ▸ Direct Distribution in the Organizer. Zip that `SlidePilot.app` (`ditto -c -k --keepParent`) and attach it to the GitHub release.

## What each build contains
- **App icon:** `SlidePilot/Resources/AppIcon.icon` (Icon Composer; design notes in [`design/app-icon`](design/app-icon/README.md)).
- **Export compliance:** `ITSAppUsesNonExemptEncryption = NO` in the generated Info.plist, so App Store Connect asks no encryption questions per build. The remote encrypts and authenticates its connection (ADR 0017), but only with CryptoKit (X25519, HKDF, ChaCha20-Poly1305, HMAC-SHA256), i.e. the encryption within Apple's operating system; the app has no cryptography of its own and no other crypto library. App Store Connect therefore needs no export documentation (no CCATS, no French encryption declaration). If App Store Connect asks anyway, the answer to "What type of encryption algorithms does your app implement?" is "None of the algorithms mentioned above". Decided for 2.0 (#41). Revisit this if the app adds a crypto library or its own implementation of an algorithm.
- **Privacy manifest:** `SlidePilot/Resources/PrivacyInfo.xcprivacy`. No tracking, no collected data. When code starts using a required-reason API (e.g. `UserDefaults`, file timestamps, disk space, system boot time), add it with its reason to `NSPrivacyAccessedAPITypes` in the same PR.
- **macOS sandbox:** App Sandbox and Hardened Runtime are on; file access is read-only for files the user selects. Writing the notes companion file (ADR 0007) will need read-write access.
