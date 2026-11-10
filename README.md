# SlidePilot Universal

PDF presenter for macOS and iPadOS, made for LaTeX Beamer slides: presenter and presentation views, notes, timer, pointer, drawing and curtain.

This repository is a from-scratch rewrite of [SlidePilot for macOS](https://github.com/SlidePilot/SlidePilot-macOS) as one SwiftUI app for **macOS 26** and **iPadOS 26**, with the original feature set preserved.

> Status: Phase 0 – Foundation. Not usable yet.

## Documentation
- [Feature parity inventory](docs/feature-parity.md): the scope of the rewrite
- [Architecture](docs/architecture.md)
- [Decisions (ADRs)](docs/decisions/)
- [User documentation of the current app](https://slidepilot.gitbook.io/slidepilot)

## Building
Requires Xcode 26 or later. Open `SlidePilot.xcodeproj` and run the `SlidePilot` scheme on "My Mac" or an iPad simulator. For signed builds, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and fill in your own bundle ID prefix and team. See [CLAUDE.md](CLAUDE.md#build-and-test) for the exact build and test commands.

## Contributing
Please read [CONTRIBUTING.md](CONTRIBUTING.md) first.

## License
[GNU General Public License v3.0](LICENSE). See [ADR 0002](docs/decisions/0002-public-repo-english-gpl.md) for the contribution terms.
