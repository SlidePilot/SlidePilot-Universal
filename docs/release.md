# Release and TestFlight

SlidePilot ships as one universal App Store app for iPadOS and macOS (ADR 0011). One App Store Connect record holds both platforms; each platform gets its own archive and upload.

## One-time setup (product owner)
- The App Store Connect record exists with the platforms iOS and macOS and the same bundle ID as the app.
- `Config/Local.xcconfig` (git-ignored) sets `BUNDLE_ID_PREFIX` and `DEVELOPMENT_TEAM` so that `$(BUNDLE_ID_PREFIX).SlidePilot` matches the record's bundle ID.
- Xcode is signed in to the developer account (Xcode ▸ Settings ▸ Apple Accounts). Automatic signing creates the distribution certificate and profiles on the first signed archive (`-allowProvisioningUpdates`).
- The current Apple Developer Program License Agreement is accepted in App Store Connect.

## Versions and build numbers
- `MARKETING_VERSION` in `Config/Shared.xcconfig` is the user-visible version.
- `CURRENT_PROJECT_VERSION` stays `1` in the repository. On upload, Xcode raises the build number to the next free one for that version and platform (`manageAppVersionAndBuildNumber` in `Config/ExportOptions-AppStore.plist`), so no commit is needed per upload.

## Archive and upload
Run from the repository root, once per platform. `./build/` is git-ignored.

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

## What each build contains
- **App icon:** `SlidePilot/Resources/AppIcon.icon` (Icon Composer, placeholder until the final icon in the release preparation issue).
- **Export compliance:** `ITSAppUsesNonExemptEncryption = NO` in the generated Info.plist. The app only uses encryption provided by the OS. Revisit this if the remote protocol adds its own encryption.
- **Privacy manifest:** `SlidePilot/Resources/PrivacyInfo.xcprivacy`. No tracking, no collected data. When code starts using a required-reason API (e.g. `UserDefaults`, file timestamps, disk space, system boot time), add it with its reason to `NSPrivacyAccessedAPITypes` in the same PR.
- **macOS sandbox:** App Sandbox and Hardened Runtime are on; file access is read-only for files the user selects. Writing the notes companion file (ADR 0007) will need read-write access.
