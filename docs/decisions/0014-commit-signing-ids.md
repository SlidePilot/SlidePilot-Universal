# 0014 – Commit the bundle ID prefix and development team

- Status: Accepted
- Date: 2026-11-14
- Supersedes: the signing consequences of [0003](0003-app-store-distribution.md) and [0011](0011-universal-purchase-and-direct-download.md)

## Context
ADR 0003 kept the real bundle ID prefix and development team out of the public repository, in a git-ignored `Config/Local.xcconfig`. Releases now run on Xcode Cloud, which only sees the repository. Without the real values it archives `org.example.SlidePilot`, which does not match the App Store Connect record, so signing and upload fail. Keeping them out would need a `ci_post_clone.sh` script and secret workflow variables.

Neither value is secret: the team ID is part of the code signature of every distributed build, and the bundle ID is listed for every App Store app. Neither allows anyone to sign or upload; that needs certificates and account access.

## Decision
- `Config/Shared.xcconfig` contains the real bundle ID prefix and development team of the App Store app.
- `Config/Local.xcconfig` stays git-ignored and optional, to override these values (e.g. a fork signed with its own team).
- Signing material (certificates, keys, profiles, API keys) is still never committed.

## Consequences
- Xcode Cloud, new clones, worktrees and cloud sessions build signed archives without extra setup.
- The bundle ID prefix contains the product owner's name; the product owner accepted that.
- GitHub Actions keeps building with `CODE_SIGNING_ALLOWED=NO`.
