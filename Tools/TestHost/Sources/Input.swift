import AppKit
import ApplicationServices

// Reads and drives the test build's user interface. Accessibility calls start
// at AXUIElementCreateApplication(target pid) and events go to that pid with
// CGEvent.postToPid, so no other app can be read or receive input.

@MainActor
final class Input {
    // MARK: Accessibility tree

    struct Node {
        let path: String
        let element: AXUIElement
        let depth: Int
    }

    /// Text outline of the app's accessibility tree. Each line starts with a
    /// path ("0.2.1") that `press` accepts.
    func tree(of target: VerifiedTarget, maxDepth: Int = 30, maxNodes: Int = 4000) -> String {
        var lines: [String] = []
        walk(root: AXUIElementCreateApplication(target.pid), maxDepth: maxDepth, maxNodes: maxNodes) { node in
            lines.append(String(repeating: "  ", count: node.depth) + "[\(node.path)] " + describe(node.element))
            return true
        }
        return lines.joined(separator: "\n")
    }

    struct Match {
        var role: String?
        var title: String?
        var identifier: String?
        var description: String?
    }

    func press(target: VerifiedTarget, path: String?, match: Match?) throws -> String {
        let element = try find(target: target, path: path, match: match)
        try checkMenuItem(element)
        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        guard result == .success else { throw PolicyError.refused("AXPress failed (\(result.rawValue))") }
        return describe(element)
    }

    /// Opens a menu bar menu (`open == true`, e.g. for a screenshot of it) or
    /// chooses the item at the end of `titles` (e.g. ["View", "Enter Full Screen"]).
    func menu(target: VerifiedTarget, titles: [String], open: Bool) throws -> String {
        guard !titles.isEmpty else { throw PolicyError.refused("empty menu path") }
        for title in titles where Policy.isBlockedMenuTitle(title) {
            throw PolicyError.refused("menu item \(title) is blocked for the test host")
        }
        let app = AXUIElementCreateApplication(target.pid)
        guard var current = attribute(app, kAXMenuBarAttribute) as AXUIElement? else {
            throw PolicyError.refused("the test build has no menu bar")
        }
        for (index, title) in titles.enumerated() {
            var container = current
            // Menu bar items and menu items hold their items in an AXMenu child.
            if index > 0, let submenu = children(of: current).first(where: { role(of: $0) == kAXMenuRole }) {
                container = submenu
            }
            guard let item = children(of: container).first(where: { (attribute($0, kAXTitleAttribute) as String?) == title }) else {
                throw PolicyError.refused("menu item \(title) not found")
            }
            current = item
        }
        try checkMenuItem(current)
        if open {
            AXUIElementPerformAction(current, kAXPressAction as CFString)
            return "opened \(titles.joined(separator: " > "))"
        }
        let result = AXUIElementPerformAction(current, kAXPressAction as CFString)
        guard result == .success else { throw PolicyError.refused("choosing \(titles.joined(separator: " > ")) failed (\(result.rawValue))") }
        return "chose \(titles.joined(separator: " > "))"
    }

    // MARK: Keyboard

    /// Presses a key combination such as "cmd+shift+right", "escape" or "a".
    func key(target: VerifiedTarget, combo: String, menuOpen: Bool) throws {
        let parts = combo.lowercased().split(separator: "+").map(String.init)
        guard let keyName = parts.last, let keyCode = Self.keyCodes[keyName] else {
            throw PolicyError.refused("unknown key in \(combo)")
        }
        var flags: CGEventFlags = []
        for modifier in parts.dropLast() {
            switch modifier {
            case "cmd", "command": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "opt", "option", "alt": flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            default: throw PolicyError.refused("unknown modifier \(modifier)")
            }
        }
        if Policy.isBlockedShortcut(key: keyName, modifiers: flags) {
            throw PolicyError.refused("\(combo) is blocked for the test host (paste/open)")
        }
        // In an open menu, Return would choose the highlighted item, which
        // bypasses the menu title check. Only Escape is allowed then.
        if menuOpen && keyName != "escape" {
            throw PolicyError.refused("a menu is open; choose items with menu/press or close it with escape")
        }
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down) else { continue }
            event.flags = flags
            event.postToPid(target.pid)
        }
    }

    /// Types text as if from the keyboard.
    func type(target: VerifiedTarget, text: String, menuOpen: Bool) async throws {
        guard !menuOpen else { throw PolicyError.refused("a menu is open; close it with escape first") }
        guard text.count <= 2000 else { throw PolicyError.refused("text is too long") }
        for character in text {
            let units = Array(String(character).utf16)
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) else { continue }
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                event.postToPid(target.pid)
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: Mouse

    // AppKit ignores mouse events posted to a process, so mouse events go
    // through the system event stream. Before each event the host checks that
    // the frontmost window at that point is a normal window of the test build;
    // otherwise it stops. The pointer is moved back afterwards.

    enum Button: String { case left, right }

    /// Clicks at a point given in the window's own coordinates (points from its
    /// top-left corner). The point must lie inside that test build window.
    func click(target: VerifiedTarget, window: WindowInfo, at point: CGPoint, button: Button, count: Int, menuOpen: Bool) async throws {
        try refuseInMenu(menuOpen)
        let location = try globalPoint(point, in: window)
        let (down, up, mouseButton): (CGEventType, CGEventType, CGMouseButton) = button == .left
            ? (.leftMouseDown, .leftMouseUp, .left) : (.rightMouseDown, .rightMouseUp, .right)
        let restore = pointerLocation()
        defer { movePointer(to: restore) }
        for click in 1...max(1, min(count, 3)) {
            for type in [down, up] {
                try post(type, at: location, button: mouseButton, clickState: click, target: target)
            }
            try await Task.sleep(for: .milliseconds(40))
        }
    }

    /// Drags along points in window coordinates, e.g. to draw on a slide.
    func drag(target: VerifiedTarget, window: WindowInfo, points: [CGPoint], menuOpen: Bool) async throws {
        try refuseInMenu(menuOpen)
        guard points.count >= 2, points.count <= 500 else { throw PolicyError.refused("a drag needs 2 to 500 points") }
        let locations = try points.map { try globalPoint($0, in: window) }
        let restore = pointerLocation()
        defer { movePointer(to: restore) }
        try post(.leftMouseDown, at: locations[0], button: .left, clickState: 1, target: target)
        do {
            for location in locations.dropFirst() {
                try await Task.sleep(for: .milliseconds(12))
                try post(.leftMouseDragged, at: location, button: .left, clickState: 1, target: target)
            }
        } catch {
            // Never leave the button pressed.
            postUnchecked(.leftMouseUp, at: locations[0], button: .left)
            throw error
        }
        try post(.leftMouseUp, at: locations[locations.count - 1], button: .left, clickState: 1, target: target)
    }

    func scroll(target: VerifiedTarget, window: WindowInfo, at point: CGPoint, dx: Int32, dy: Int32, menuOpen: Bool) throws {
        try refuseInMenu(menuOpen)
        let location = try globalPoint(point, in: window)
        try checkFrontmost(at: location, target: target)
        let restore = pointerLocation()
        defer { movePointer(to: restore) }
        movePointer(to: location)
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0) else { return }
        event.location = location
        event.post(tap: .cghidEventTap)
    }

    /// In an open menu a click could choose a blocked item; use menu/press or escape.
    private func refuseInMenu(_ menuOpen: Bool) throws {
        if menuOpen {
            throw PolicyError.refused("a menu is open; choose items with menu/press or close it with escape")
        }
    }

    private func globalPoint(_ point: CGPoint, in window: WindowInfo) throws -> CGPoint {
        let location = CGPoint(x: window.frame.minX + point.x, y: window.frame.minY + point.y)
        guard window.frame.contains(location) else {
            throw PolicyError.refused("point \(point) is outside window \(window.id)")
        }
        return location
    }

    private func post(_ type: CGEventType, at location: CGPoint, button: CGMouseButton, clickState: Int, target: VerifiedTarget) throws {
        try checkFrontmost(at: location, target: target)
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: location, mouseButton: button) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
        event.post(tap: .cghidEventTap)
    }

    private func postUnchecked(_ type: CGEventType, at location: CGPoint, button: CGMouseButton) {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: location, mouseButton: button)?.post(tap: .cghidEventTap)
    }

    /// The frontmost visible window at `location` (in z-order, including the
    /// menu bar, Dock, notifications and other apps) must be a test build
    /// window below menu level. Anything else in front stops the event.
    private func checkFrontmost(at location: CGPoint, target: VerifiedTarget) throws {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        for info in windows {
            guard let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo), bounds.contains(location) else { continue }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha <= 0 { continue }
            let pid = info[kCGWindowOwnerPID as String] as? Int32
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            guard pid == target.pid, layer < Int(CGWindowLevelForKey(.popUpMenuWindow)) else {
                throw PolicyError.refused("another window is in front of the test build at \(location); nothing was clicked")
            }
            return
        }
        throw PolicyError.refused("no test build window at \(location)")
    }

    private func pointerLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    private func movePointer(to location: CGPoint) {
        CGWarpMouseCursorPosition(location)
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    // MARK: Menus

    /// A menu (menu bar or context menu) is open when one of the app's AXMenu
    /// elements has a size; closed menus report an empty frame.
    func isMenuOpen(target: VerifiedTarget) -> Bool {
        var open = false
        walk(root: AXUIElementCreateApplication(target.pid), maxDepth: 12, maxNodes: 8000) { node in
            if role(of: node.element) == kAXMenuRole, let frame = frame(of: node.element), frame.width > 0, frame.height > 0 {
                open = true
                return false
            }
            return true
        }
        return open
    }

    // MARK: Helpers

    private func find(target: VerifiedTarget, path: String?, match: Match?) throws -> AXUIElement {
        let root = AXUIElementCreateApplication(target.pid)
        var found: AXUIElement?
        walk(root: root, maxDepth: 30, maxNodes: 8000) { node in
            if let path, node.path == path { found = node.element; return false }
            if let match, path == nil, matches(node.element, match) { found = node.element; return false }
            return true
        }
        guard let found else { throw PolicyError.refused("no matching element") }
        return found
    }

    private func matches(_ element: AXUIElement, _ match: Match) -> Bool {
        if let role = match.role, self.role(of: element) != role { return false }
        if let title = match.title, (attribute(element, kAXTitleAttribute) as String?) != title { return false }
        if let id = match.identifier, (attribute(element, kAXIdentifierAttribute) as String?) != id { return false }
        if let description = match.description, (attribute(element, kAXDescriptionAttribute) as String?) != description { return false }
        return match.role != nil || match.title != nil || match.identifier != nil || match.description != nil
    }

    /// Menu items (also in context menus) are checked against the blocked
    /// titles, including every parent menu (e.g. AutoFill > Contact…).
    private func checkMenuItem(_ element: AXUIElement) throws {
        var current: AXUIElement? = element
        var depth = 0
        while let item = current, depth < 12 {
            let itemRole = role(of: item)
            if itemRole == kAXMenuItemRole || itemRole == kAXMenuBarItemRole {
                let title = attribute(item, kAXTitleAttribute) as String? ?? ""
                if Policy.isBlockedMenuTitle(title) {
                    throw PolicyError.refused("menu item \(title) is blocked for the test host")
                }
                if let identifier: String = attribute(item, kAXIdentifierAttribute), Policy.isBlockedMenuIdentifier(identifier) {
                    throw PolicyError.refused("menu item \(title) (\(identifier)) is blocked for the test host")
                }
                let commandChar = (attribute(item, kAXMenuItemCmdCharAttribute) as String?)?.lowercased()
                if itemRole == kAXMenuItemRole, let commandChar, ["v", "o"].contains(commandChar) {
                    throw PolicyError.refused("menu item \(title) (⌘\(commandChar.uppercased())) is blocked for the test host")
                }
            }
            current = attribute(item, kAXParentAttribute) as AXUIElement?
            depth += 1
        }
    }

    private func walk(root: AXUIElement, maxDepth: Int, maxNodes: Int, visit: (Node) -> Bool) {
        var stack: [Node] = [Node(path: "0", element: root, depth: 0)]
        var count = 0
        while let node = stack.popLast(), count < maxNodes {
            count += 1
            guard visit(node) else { return }
            guard node.depth < maxDepth else { continue }
            let kids = children(of: node.element)
            for (index, child) in kids.enumerated().reversed() {
                stack.append(Node(path: "\(node.path).\(index)", element: child, depth: node.depth + 1))
            }
        }
    }

    private func describe(_ element: AXUIElement) -> String {
        var parts = [role(of: element)]
        if let subrole: String = attribute(element, kAXSubroleAttribute) { parts.append("(\(subrole))") }
        for (label, key) in [("title", kAXTitleAttribute), ("label", kAXDescriptionAttribute),
                             ("id", kAXIdentifierAttribute), ("help", kAXHelpAttribute)] {
            if let text: String = attribute(element, key), !text.isEmpty {
                parts.append("\(label)=\"\(text.prefix(80))\"")
            }
        }
        if let value = attribute(element, kAXValueAttribute) as CFTypeRef? {
            let text: String? = switch CFGetTypeID(value) {
            case CFStringGetTypeID(): (value as! String)
            case CFNumberGetTypeID(), CFBooleanGetTypeID(): "\(value)"
            default: nil
            }
            if let text, !text.isEmpty { parts.append("value=\"\(text.prefix(80))\"") }
        }
        if let enabled: Bool = attribute(element, kAXEnabledAttribute), !enabled { parts.append("disabled") }
        if let frame = frame(of: element) {
            parts.append("frame=(\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width)),\(Int(frame.height)))")
        }
        return parts.joined(separator: " ")
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute) as AXValue?,
              let size = attribute(element, kAXSizeAttribute) as AXValue? else { return nil }
        var point = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &extent) else { return nil }
        return CGRect(origin: point, size: extent)
    }

    private func role(of element: AXUIElement) -> String {
        attribute(element, kAXRoleAttribute) ?? "?"
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) ?? []
    }

    private func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value else { return nil }
        return value as? T
    }

    // MARK: Key codes (ANSI layout)

    static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
        "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
        "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38,
        "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
        "`": 50, "return": 36, "enter": 76, "tab": 48, "space": 49, "delete": 51,
        "backspace": 51, "escape": 53, "esc": 53, "forwarddelete": 117, "home": 115,
        "end": 119, "pageup": 116, "pagedown": 121, "left": 123, "right": 124,
        "down": 125, "up": 126, "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96,
        "f6": 97, "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    ]
}
