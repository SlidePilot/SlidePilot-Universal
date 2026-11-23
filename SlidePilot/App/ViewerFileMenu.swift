#if os(macOS)
import AppKit

/// Hides the document system's saving items in the File menu (#136).
///
/// SlidePilot only views PDFs, but `DocumentGroup` puts Save, Save As…, Duplicate,
/// Rename…, Move To… and Revert To next to Close, and Save fails with an error. SwiftUI
/// can only replace that command group as a whole, which also drops Close, Open Recent
/// and Share, so the items are hidden in the menu SwiftUI built instead. A hidden item
/// takes no part in key equivalent matching, so ⌘S and ⇧⌘S do nothing. Found by trying
/// it out in the test host:
/// - The items must stay in the menu with their actions: AppKit only adds Share while
///   `NSDocument` validates them.
/// - Save As and Duplicate are alternates (Option key), and NSMenu always shows one
///   item of an alternate group, so they lose that flag and get a target without their
///   action, which keeps `NSDocument` from enabling them.
/// - AppKit shows Revert To again while it or its entries have their actions, so they
///   lose them.
/// - SwiftUI rebuilds the menu when the focus changes and while it opens, so new items
///   are handled synchronously as soon as they are added. The notification is AppKit
///   glue, not app state.
@MainActor
final class ViewerFileMenu {
    /// The `NSDocument` actions that save, copy, move, lock or revert a document.
    private static let savingActions: Set<Selector> = [
        #selector(NSDocument.save(_:)),
        #selector(NSDocument.saveAs(_:)),
        #selector(NSDocument.saveTo(_:)),
        #selector(NSDocument.duplicate(_:)),
        #selector(NSDocument.rename(_:)),
        #selector(NSDocument.move(_:)),
        #selector(NSDocument.revertToSaved(_:)),
        #selector(NSDocument.browseVersions(_:)),
        #selector(NSDocument.lock(_:)),
        #selector(NSDocument.unlock(_:)),
    ]

    /// The alternates that NSMenu would show again.
    private static let alternateActions: Set<Selector> = [
        #selector(NSDocument.saveAs(_:)),
        #selector(NSDocument.duplicate(_:)),
    ]

    /// The Revert To entries that make AppKit show Revert To again.
    private static let versionActions: Set<Selector> = [
        #selector(NSDocument.revertToSaved(_:)),
        #selector(NSDocument.browseVersions(_:)),
    ]

    /// Responds to none of the saving actions. It also marks Revert To once its entries
    /// lost their actions. Menu items hold their target weakly, so this keeps it alive.
    private let inertTarget = NSObject()
    private var observer: (any NSObjectProtocol)?

    /// Starts hiding the items; they stay hidden for as long as the app runs.
    func start() {
        guard observer == nil else { return }
        hideSavingItems()
        // No queue: SwiftUI rebuilds the menu while it opens, so a later pass would let
        // the items show. Hiding changes no indexes, so SwiftUI's update in progress is
        // not disturbed, and it posts no add notification.
        observer = NotificationCenter.default.addObserver(
            forName: NSMenu.didAddItemNotification, object: nil, queue: nil
        ) { [weak self] _ in
            // AppKit menus are main-thread only; the check keeps a stray change elsewhere
            // from trapping. The main menu itself is never changed off the main thread.
            guard Thread.isMainThread else { return }
            MainActor.assumeIsolated {
                self?.hideSavingItems()
            }
        }
    }

    /// Hides the saving items in the top-level menus.
    private func hideSavingItems() {
        guard let mainMenu = NSApp.mainMenu else { return }
        for case let menu? in mainMenu.items.map(\.submenu) {
            for item in menu.items where item.target === inertTarget || Self.isSaving(item) {
                // Revert To starts as a plain item with the revert action; AppKit turns
                // it into a submenu later.
                for entry in [item] + (item.submenu?.items ?? []) {
                    if let action = entry.action, Self.versionActions.contains(action) {
                        entry.action = nil
                        setInertTarget(of: item)
                    }
                }
                if let action = item.action, Self.alternateActions.contains(action) {
                    if item.isAlternate {
                        item.isAlternate = false
                    }
                    setInertTarget(of: item)
                }
                if !item.isHidden {
                    item.isHidden = true
                }
            }
        }
    }

    private func setInertTarget(of item: NSMenuItem) {
        if item.target !== inertTarget {
            item.target = inertTarget
        }
    }

    /// A saving action, or the Revert To submenu, whose entries are all saving actions.
    private static func isSaving(_ item: NSMenuItem) -> Bool {
        if let action = item.action, savingActions.contains(action) { return true }
        guard let submenu = item.submenu, !submenu.items.isEmpty else { return false }
        return submenu.items.allSatisfy { $0.action.map(savingActions.contains) ?? false }
    }
}
#endif
