# 0010 – Native design first

- Status: Accepted
- Date: 2026-11-10

## Context
The old app used many custom AppKit controls: color swatch and icon buttons, a custom time view, a custom split view, a custom notice banner, a drag-and-drop layout editor and a third-party preferences window. On macOS 26 and iPadOS 26, system components adopt Liquid Glass, accessibility and platform conventions automatically; custom controls do not.

## Decision
The app must look and feel as native as possible on macOS 26 and iPadOS 26.
- Use standard system components wherever one exists: `NavigationSplitView`, toolbars, `.inspector`, sheets, popovers, the `Settings` scene, menu bar commands and keyboard shortcuts via `Commands`, standard buttons, pickers, toggles, `ColorPicker`, steppers, SF Symbols, system colors and fonts.
- Liquid Glass comes from using these components. It is never imitated by hand.
- **Feature parity means the same functionality, not the same look.** Old custom controls are not recreated. Each one is mapped to the closest native equivalent (column "Native replacement" in `docs/feature-parity.md`).
- Custom drawing is allowed only where no system component exists: the **slide surface**, the **pointer overlay** on the presentation, and the **drawing layer**. On iPad, the PencilKit tool picker is evaluated for drawing.
- Every other custom UI element must be justified in its PR.
- Light and dark mode, Dynamic Type on iPad, VoiceOver labels and keyboard navigation are part of the Definition of Done for every feature.

## Consequences
- A `design-reviewer` agent checks every UI PR against Apple's Human Interface Guidelines and this ADR: custom controls, hard-coded colors and fonts, missing accessibility. It is part of the `implement-issue` skill.
- Some interactions change shape, e.g. the drag-and-drop layout editor becomes a `Form` with pickers. Such changes are noted in the parity doc and confirmed by the product owner when the feature is built.
- Where SwiftUI has no resizable split on iPad, a custom divider needs an explicit justification.
