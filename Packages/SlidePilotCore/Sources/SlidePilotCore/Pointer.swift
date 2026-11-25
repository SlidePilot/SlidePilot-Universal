import CoreGraphics
import Foundation
import Observation

/// The shapes a pointer can have (PTR-03, PTR-04). Cursor and hand are the system's
/// pointer images; the other shapes are drawn from a `PointerConfiguration`.
public enum PointerShape: String, Codable, Sendable, Hashable, CaseIterable {
    case target, dot, circle, plus, cross, square, cursor, hand

    /// Whether the shape is a system pointer image instead of a drawn shape.
    public var isSystemImage: Bool { self == .cursor || self == .hand }
}

/// A color stored platform-neutrally as sRGB components, 0…1 (PTR-05: not an archived
/// `NSColor`).
public struct PointerColor: Codable, Sendable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let black = PointerColor(red: 0, green: 0, blue: 0)
    public static let white = PointerColor(red: 1, green: 1, blue: 1)
    /// The old app's `NSColor.systemRed` in its light appearance.
    public static let red = PointerColor(red: 1, green: 59.0 / 255, blue: 48.0 / 255)
}

/// How a pointer looks (PTR-03). Sizes are points; a value a shape does not use is ignored.
/// The pointer editor (PTR-04) edits one of these for the Individual appearance.
public struct PointerConfiguration: Codable, Sendable, Hashable {
    public var shape: PointerShape
    public var size: Double
    public var thickness: Double
    public var color: PointerColor
    public var borderWidth: Double
    public var borderColor: PointerColor
    public var shadowWidth: Double

    public init(
        shape: PointerShape,
        size: Double = 0,
        thickness: Double = 0,
        color: PointerColor = .black,
        borderWidth: Double = 0,
        borderColor: PointerColor = .black,
        shadowWidth: Double = 0
    ) {
        self.shape = shape
        self.size = size
        self.thickness = thickness
        self.color = color
        self.borderWidth = borderWidth
        self.borderColor = borderColor
        self.shadowWidth = shadowWidth
    }

    // The old app's presets (PTR-03, `PointerView.swift:74-79`).
    public static let cursor = PointerConfiguration(shape: .cursor)
    public static let hand = PointerConfiguration(shape: .hand)
    public static let target = PointerConfiguration(
        shape: .target, size: 44, thickness: 3, color: .black, borderWidth: 2, borderColor: .white
    )
    public static let targetRed = PointerConfiguration(shape: .target, size: 44, thickness: 3, color: .red)
    public static let circle = PointerConfiguration(shape: .circle, size: 20, thickness: 3, color: .white, shadowWidth: 10)
    public static let dot = PointerConfiguration(
        shape: .dot, size: 10, color: .black, borderWidth: 5, borderColor: .white, shadowWidth: 10
    )
    /// The laser pointer's dot while it hovers (PTR-08), in the strokes' color.
    public static let laserDot = PointerConfiguration(shape: .dot, size: 12, color: LaserTrail.color, shadowWidth: 4)
    /// The custom pointer until the user edits it (PTR-05).
    public static let defaultIndividual = target
}

/// The entries of Pointer Appearance (PTR-02), in the old menu's order (⌘1…⌘7), then the
/// laser pointer (⌘8, PTR-08).
public enum PointerAppearance: String, Codable, Sendable, CaseIterable {
    case cursor, hand, dot, circle, targetBlack, targetRed, individual, laser

    /// The pointer of this appearance. `individual` is the custom pointer of the pointer
    /// editor (PTR-04, PTR-05).
    public func configuration(individual: PointerConfiguration) -> PointerConfiguration {
        switch self {
        case .cursor: .cursor
        case .hand: .hand
        case .dot: .dot
        case .circle: .circle
        case .targetBlack: .target
        case .targetRed: .targetRed
        case .individual: individual
        case .laser: .laserDot
        }
    }

    /// The digit of its ⌘ shortcut, 1…8.
    public var shortcutDigit: Int {
        Self.allCases.firstIndex(of: self)! + 1
    }
}

/// The pointer of one document (PTR-01): whether it is shown, how it looks and where the
/// presenter points. Display state and appearance are per-document settings (PTR-07).
/// A class, so a moving pointer only redraws the views that read its location.
@MainActor
@Observable
public final class PointerState {
    /// Hidden when a document opens (the old app's default). On touch devices it only
    /// controls hover pointing (trackpad, mouse, Apple Pencil hover); a finger points with
    /// the double tap and hold gesture either way (PTR-01).
    public var isShown: Bool {
        didSet {
            if !isShown {
                presenterEnded()
                removeLaserStrokes()
            }
        }
    }
    /// Whether a finger holds the pointer with the double tap and hold gesture. The pointer
    /// is visible then, also while `isShown` is off.
    public private(set) var isTouchPointing = false
    /// The old app starts with the system cursor.
    public var appearance: PointerAppearance {
        didSet {
            if appearance != .laser { removeLaserStrokes() }
        }
    }
    /// The laser pointer's strokes (PTR-08). Never saved.
    public private(set) var laser = LaserTrail()
    /// Where the presenter points on the current slide, 0…1 with the origin top left;
    /// `nil` while the mouse or finger is not on the slide.
    public private(set) var presenterLocation: CGPoint?

    public init(isShown: Bool = false, appearance: PointerAppearance = .cursor) {
        self.isShown = isShown
        self.appearance = appearance
    }

    /// The presenter's pointer moved to `point` in a slide of `size` (both in the slide's
    /// own coordinates, origin top left). Outside the slide the pointer hides.
    public func presenterMoved(to point: CGPoint, inSlideOfSize size: CGSize) {
        guard isShown, !isTouchPointing else { return }
        moveLocation(to: point, inSlideOfSize: size)
    }

    /// A finger holding the pointer (double tap and hold) moved to `point`; it points
    /// whether or not the pointer is shown. Outside the slide the pointer hides until the
    /// finger comes back.
    public func touchMoved(to point: CGPoint, inSlideOfSize size: CGSize) {
        if !isTouchPointing {
            isTouchPointing = true
        }
        moveLocation(to: point, inSlideOfSize: size)
    }

    /// The finger holding the pointer lifted, or the touch was cancelled.
    public func touchEnded() {
        guard isTouchPointing else { return }
        isTouchPointing = false
        clearLocation()
    }

    private func clearLocation() {
        if presenterLocation != nil {
            presenterLocation = nil
        }
    }

    private func moveLocation(to point: CGPoint, inSlideOfSize size: CGSize) {
        let location = Self.relativeLocation(of: point, inSlideOfSize: size)
        if location != presenterLocation {
            presenterLocation = location
        }
    }

    /// The mouse or Pencil left the slide. A finger holding the pointer keeps it.
    public func presenterEnded() {
        guard !isTouchPointing else { return }
        clearLocation()
    }

    // MARK: Laser pointer (PTR-08)

    /// Whether the presenter draws laser strokes: the pointer is shown with Laser.
    public var isLaserActive: Bool { isShown && appearance == .laser }

    /// Whether the current drag was cut off by `clearLaser()`; it draws nothing more until
    /// it ends, so a slide change mid-drag leaves the new slide clean.
    @ObservationIgnored private var isLaserDragInterrupted = false

    /// The presenter's mouse, finger or Pencil drags from `start` to `point` in a slide of
    /// `size` (slide coordinates, origin top left). The drag's first change starts a stroke
    /// at `start`; later ones continue it. Points beyond the slide's edge are kept, so a
    /// stroke may leave the slide and come back.
    public func laserDragged(from start: CGPoint, to point: CGPoint, inSlideOfSize size: CGSize, time: TimeInterval) {
        guard isLaserActive, !isLaserDragInterrupted, size.width > 0, size.height > 0 else { return }
        func relative(_ point: CGPoint) -> RelativePoint {
            RelativePoint(x: point.x / size.width, y: point.y / size.height)
        }
        if !laser.isDrawing {
            laser.begin(at: relative(start), time: time)
        }
        laser.extend(to: relative(point))
    }

    /// A drag that starts and stays at `point`, e.g. in tests.
    public func laserMoved(to point: CGPoint, inSlideOfSize size: CGSize, time: TimeInterval) {
        laserDragged(from: point, to: point, inSlideOfSize: size, time: time)
    }

    /// The drag ended or was cancelled, or its view went away; the strokes fade after a
    /// moment. The next drag draws again.
    public func laserEnded(time: TimeInterval) {
        isLaserDragInterrupted = false
        guard laser.isDrawing else { return }
        laser.end(time: time)
    }

    /// Removes the strokes at once on a slide change. A drag in progress draws nothing
    /// more until it ends.
    public func clearLaser() {
        // A second slide change in the same drag keeps it cut off.
        let interrupts = laser.isDrawing || isLaserDragInterrupted
        removeLaserStrokes()
        isLaserDragInterrupted = interrupts
    }

    /// Pointer hidden or another appearance: the laser's gesture turns off, so no drag
    /// goes on to be cut off.
    private func removeLaserStrokes() {
        isLaserDragInterrupted = false
        if !laser.isEmpty || laser.isDrawing {
            laser.clear()
        }
    }

    /// Drops strokes that have faded out.
    public func removeExpiredLaser(at time: TimeInterval) {
        guard let removalTime = laser.removalTime, time >= removalTime else { return }
        laser.removeExpired(at: time)
    }

    /// Where the audience sees the pointer: the presenter's, else a remote controller's.
    /// Nothing while the pointer is hidden, also not the remote's (DEF-14); a finger
    /// holding the pointer shows only its own location.
    public func visibleLocation(remote: CGPoint?) -> CGPoint? {
        if isTouchPointing { return presenterLocation }
        guard isShown else { return nil }
        return presenterLocation ?? remote.flatMap { Self.isOnSlide($0) ? $0 : nil }
    }

    /// `point` relative to the slide, or `nil` outside 0…1 (PTR-01).
    public nonisolated static func relativeLocation(of point: CGPoint, inSlideOfSize size: CGSize) -> CGPoint? {
        guard size.width > 0, size.height > 0 else { return nil }
        let relative = CGPoint(x: point.x / size.width, y: point.y / size.height)
        return isOnSlide(relative) ? relative : nil
    }

    private nonisolated static func isOnSlide(_ point: CGPoint) -> Bool {
        (0...1).contains(point.x) && (0...1).contains(point.y)
    }
}

/// The parts of a drawn pointer, laid out like the old app (`PointerView.swift:145-417`).
/// Coordinates are points in a square canvas of `side` points whose center is the hotspot.
public struct PointerDrawing: Sendable, Equatable {
    public enum Part: Sendable, Equatable {
        case fillEllipse(CGRect, PointerColor)
        case strokeEllipse(CGRect, lineWidth: Double, PointerColor)
        case fillRect(CGRect, PointerColor)
    }

    public var side: Double
    /// Drawn back to front.
    public var parts: [Part]
    /// Degrees around the center (the cross is a rotated plus).
    public var rotation: Double
    /// Radius of a black shadow around all parts; 0 for none.
    public var shadowRadius: Double

    /// `nil` for the system images (cursor, hand).
    public init?(_ configuration: PointerConfiguration) {
        let size = configuration.size
        let thickness = configuration.thickness
        let border = configuration.borderWidth
        let color = configuration.color
        let borderColor = configuration.borderColor
        // Room for the shadow on both sides, like the old app.
        let shadowPadding = configuration.shadowWidth * 3.5
        let hasBorder = border != 0
        rotation = 0
        shadowRadius = max(configuration.shadowWidth, 0)

        switch configuration.shape {
        case .cursor, .hand:
            return nil
        case .target, .circle:
            side = size + thickness + border + shadowPadding
            let side = side
            let ringInset = border + (thickness + shadowPadding) / 2
            let borderInset = (border + shadowPadding) / 2
            let ring = Part.strokeEllipse(Self.inset(side, ringInset), lineWidth: thickness, color)
            let ringBorder = Part.strokeEllipse(Self.inset(side, borderInset), lineWidth: border, borderColor)
            let rings = (hasBorder ? [ringBorder] : []) + [ring]
            if configuration.shape == .circle {
                parts = rings
            } else {
                let center = thickness * 1.4
                let centerDot = Part.fillEllipse(Self.centered(side, center), color)
                let centerBorder = Part.fillEllipse(Self.centered(side, center + border * 2), borderColor)
                parts = (hasBorder ? [centerBorder] : []) + [centerDot] + rings
            }
        case .dot, .square:
            side = size + border + shadowPadding
            let side = side
            let isDot = configuration.shape == .dot
            let shape = Self.inset(side, (border + shadowPadding) / 2)
            let shapeBorder = Self.inset(side, shadowPadding / 2)
            parts = (hasBorder ? [isDot ? .fillEllipse(shapeBorder, borderColor) : .fillRect(shapeBorder, borderColor)] : [])
                + [isDot ? .fillEllipse(shape, color) : .fillRect(shape, color)]
        case .plus, .cross:
            side = size + border + shadowPadding
            let side = side
            let length = side - border - shadowPadding
            let borderLength = side - shadowPadding
            let vertical = CGRect(x: (side - thickness) / 2, y: (side - length) / 2, width: thickness, height: length)
            let horizontal = CGRect(x: (side - length) / 2, y: (side - thickness) / 2, width: length, height: thickness)
            let verticalBorder = CGRect(
                x: (side - thickness - border) / 2, y: (side - borderLength) / 2,
                width: thickness + border, height: borderLength
            )
            let horizontalBorder = CGRect(
                x: (side - borderLength) / 2, y: (side - thickness - border) / 2,
                width: borderLength, height: thickness + border
            )
            parts = (hasBorder ? [.fillRect(verticalBorder, borderColor), .fillRect(horizontalBorder, borderColor)] : [])
                + [.fillRect(vertical, color), .fillRect(horizontal, color)]
            if configuration.shape == .cross {
                rotation = 45
            }
        }
    }

    private static func inset(_ side: Double, _ inset: Double) -> CGRect {
        CGRect(x: inset, y: inset, width: side - 2 * inset, height: side - 2 * inset)
    }

    private static func centered(_ side: Double, _ diameter: Double) -> CGRect {
        CGRect(x: (side - diameter) / 2, y: (side - diameter) / 2, width: diameter, height: diameter)
    }
}

// MARK: - Pointer editor (PTR-04)

/// The slider ranges the pointer editor offers for one shape (PTR-04,
/// `PointerEditorViewController.swift:73-79`).
public struct PointerEditorLimits: Sendable, Equatable {
    public var size: ClosedRange<Double>
    /// `nil` for shapes without a thickness (dot and square).
    public var thickness: ClosedRange<Double>?
    public var borderWidth: ClosedRange<Double> { 0...50 }
    public var shadowWidth: ClosedRange<Double> { 0...50 }
}

extension PointerShape {
    /// The shapes of the editor's picker, in the old app's order.
    public static let editorShapes: [PointerShape] = [.target, .dot, .circle, .plus, .cross, .square]

    /// The editor's ranges for this shape; `nil` for the system images.
    public var editorLimits: PointerEditorLimits? {
        switch self {
        case .cursor, .hand: nil
        case .target: PointerEditorLimits(size: 35...150, thickness: 2...50)
        case .circle, .plus, .cross: PointerEditorLimits(size: 5...100, thickness: 2...50)
        case .dot, .square: PointerEditorLimits(size: 5...100, thickness: nil)
        }
    }
}

extension PointerConfiguration {
    /// This pointer with another shape. The values are kept and only moved into the new
    /// shape's ranges; the old app reset them to the shape's defaults (DEF-14).
    public func withShape(_ shape: PointerShape) -> PointerConfiguration {
        var configuration = self
        configuration.shape = shape
        return configuration.clampedForEditor()
    }

    /// This pointer with every value inside the editor's ranges, so a hand-edited or
    /// outdated stored pointer still fits the sliders. A system image becomes the default
    /// custom pointer, which the editor cannot show.
    public func clampedForEditor() -> PointerConfiguration {
        guard let limits = shape.editorLimits else { return .defaultIndividual }
        var configuration = self
        configuration.size = Self.clamp(size, to: limits.size)
        if let thickness = limits.thickness {
            configuration.thickness = Self.clamp(self.thickness, to: thickness)
        }
        configuration.borderWidth = Self.clamp(borderWidth, to: limits.borderWidth)
        configuration.shadowWidth = Self.clamp(shadowWidth, to: limits.shadowWidth)
        configuration.color = color.clamped
        configuration.borderColor = borderColor.clamped
        return configuration
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        // NaN would pass `min`/`max` unchanged.
        value.isNaN ? range.lowerBound : min(max(value, range.lowerBound), range.upperBound)
    }
}

extension PointerColor {
    /// The color in sRGB, e.g. from a color picker. Colors outside sRGB (Display P3) are
    /// moved to its edge; `nil` if the color cannot be converted (patterns).
    public init?(_ cgColor: CGColor) {
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = cgColor.converted(to: sRGB, intent: .defaultIntent, options: nil),
              let components = converted.components, components.count == 4
        else { return nil }
        self = PointerColor(
            red: Double(components[0]), green: Double(components[1]),
            blue: Double(components[2]), alpha: Double(components[3])
        ).clamped
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    /// Every component in 0…1.
    var clamped: PointerColor {
        func clamp(_ value: Double) -> Double { value.isNaN ? 0 : min(max(value, 0), 1) }
        return PointerColor(red: clamp(red), green: clamp(green), blue: clamp(blue), alpha: clamp(alpha))
    }
}
