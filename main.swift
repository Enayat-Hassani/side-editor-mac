// Side Edit: a minimal text editor panel that opens over the right side of the front Finder window,
// where the preview pane sits, on Finder's own Space (also when Finder is full screen).
// Every close saves first: Esc, ⌘W, ⌘S, the close button, ⌘Q, or clicking back into Finder.
// ⌘ or ⇧ + double-click in Finder, and ⌘E in the panel, open the file in its usual app (.sql → MySQL Workbench/DBeaver, else VS Code/Antigravity), ⌘⌫ moves to Trash (without saving).
import AppKit

/// Apps for ⌘E / ⌘-double-click, first installed wins. Optional ~/.config/side-edit/apps.json overrides, e.g.
/// {"sql": ["TablePlus"], "default": ["Zed", "Visual Studio Code"]}  (keys are extensions; "default" is everything else)
var appsByExtension: [String: [String]] = ["sql": ["MySQLWorkbench", "DBeaver"], "default": ["Visual Studio Code", "Antigravity"]]
if let data = try? Data(contentsOf: URL(fileURLWithPath: NSHomeDirectory() + "/.config/side-edit/apps.json")),
   let user = try? JSONDecoder().decode([String: [String]].self, from: data) {
    appsByExtension.merge(user) { _, new in new }
}

func externalApp(for url: URL) -> URL? {
    let names = (appsByExtension[url.pathExtension.lowercased()] ?? []) + (appsByExtension["default"] ?? [])
    for name in names {
        for dir in ["/Applications", NSHomeDirectory() + "/Applications"] {
            let app = URL(fileURLWithPath: "\(dir)/\(name).app")
            if FileManager.default.fileExists(atPath: app.path) { return app }
        }
    }
    return nil
}

/// Frame covering the right part of the frontmost Finder window, in Cocoa (bottom-left) coordinates.
func finderSideFrame() -> NSRect? {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
          let primary = NSScreen.screens.first else { return nil }
    for w in list where (w[kCGWindowOwnerName as String] as? String) == "Finder" && (w[kCGWindowLayer as String] as? Int) == 0 {
        guard let b = w[kCGWindowBounds as String] as? [String: CGFloat],
              let x = b["X"], let y = b["Y"], let width = b["Width"], let height = b["Height"], width > 400, height > 300 else { continue }  // height check skips the full-screen toolbar strip
        let panelWidth = min(620, max(380, width * 0.42))
        return NSRect(x: x + width - panelWidth, y: primary.frame.height - y - height, width: panelWidth, height: height)
    }
    return nil
}

@objc(Doc) final class Doc: NSDocument, NSTextStorageDelegate, NSWindowDelegate {
    var text = ""
    weak var view: NSTextView?
    var isMarkdown: Bool { fileURL?.pathExtension.lowercased() == "md" }
    var bodyFont: NSFont { isMarkdown ? .systemFont(ofSize: 14) : .monospacedSystemFont(ofSize: 13, weight: .regular) }

    override class var autosavesInPlace: Bool { false }  // no background autosave or versions; closing saves instead

    // Edited = text differs from the file as opened; catches every change, and undoing back counts as clean.
    override var isDocumentEdited: Bool { (view?.string ?? text) != text }

    override func read(from data: Data, ofType typeName: String) throws {
        guard let s = String(data: data, encoding: .utf8) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadInapplicableStringEncodingError)
        }
        text = s
    }

    override func data(ofType typeName: String) throws -> Data { Data((view?.string ?? text).utf8) }

    override func makeWindowControllers() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 720),
                            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden  // no file name or icon in the title bar
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        // Join whatever Space Finder is on (including a full-screen one) instead of opening a new one.
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self  // so typing goes into the document's undo history and marks it edited

        let scroll = NSTextView.scrollableTextView()  // stock setup: wraps to the panel width
        let tv = scroll.documentView as! NSTextView
        tv.isRichText = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.textContainerInset = NSSize(width: 20, height: 16)
        let para = NSMutableParagraphStyle(); para.lineSpacing = 3; para.paragraphSpacing = 2
        tv.defaultParagraphStyle = para
        tv.font = bodyFont
        tv.textColor = .textColor
        tv.typingAttributes = [.font: bodyFont, .foregroundColor: NSColor.textColor, .paragraphStyle: para]
        tv.string = text
        if isMarkdown { tv.textStorage?.delegate = self; styleMarkdown(tv.textStorage!) }
        panel.contentView = scroll
        panel.standardWindowButton(.documentIconButton)?.isHidden = true
        view = tv

        addWindowController(NSWindowController(window: panel))
        if let frame = finderSideFrame() { panel.setFrame(frame, display: true) } else { panel.center() }
        NSApp.activate(ignoringOtherApps: true)  // accessory apps aren't activated on open; take the keyboard
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(tv)
        tv.setSelectedRange(NSRange(location: 0, length: 0))
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { undoManager }

    // Esc, ⌘W and the close button: save edits instead of showing the "Save changes?" prompt.
    // saveAndClose closes the document itself, so the standard close callback is never needed.
    override func canClose(withDelegate delegate: Any, shouldClose: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        if isDocumentEdited { saveAndClose(nil) } else { close() }
    }

    func textStorage(_ ts: NSTextStorage, didProcessEditing mask: NSTextStorageEditActions, range: NSRange, changeInLength: Int) {
        if mask.contains(.editedCharacters) { styleMarkdown(ts) }
    }

    /// Markdown headings larger and bold in the accent colour; everything else plain.
    func styleMarkdown(_ ts: NSTextStorage) {
        let all = NSRange(location: 0, length: ts.length)
        let para = NSMutableParagraphStyle(); para.lineSpacing = 3; para.paragraphSpacing = 2
        ts.addAttributes([.font: bodyFont, .foregroundColor: NSColor.textColor, .paragraphStyle: para], range: all)
        let re = try! NSRegularExpression(pattern: "^#{1,6} .*$", options: .anchorsMatchLines)
        for m in re.matches(in: ts.string, range: all) {
            ts.addAttributes([.font: NSFont.systemFont(ofSize: 16, weight: .semibold), .foregroundColor: NSColor.controlAccentColor], range: m.range)
        }
    }

    @objc func openInBigEditor(_ sender: Any?) {
        guard let url = fileURL, let app = externalApp(for: url) else { return }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc func saveAndClose(_ sender: Any?) {
        guard let url = fileURL, let type = fileType else { return }
        save(to: url, ofType: type, for: .saveOperation) { err in
            if let err { self.presentError(err) } else { self.close() }
        }
    }

    @objc func moveToTrash(_ sender: Any?) {
        guard let url = fileURL else { return }
        close()
        NSWorkspace.shared.recycle([url])
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    // Plain double-click opens the side panel; ⌘ or ⇧ held while opening hands the file to its usual app instead.
    func application(_ application: NSApplication, open urls: [URL]) {
        let external = !NSEvent.modifierFlags.isDisjoint(with: [.command, .shift])
        for url in urls {
            if external, let app = externalApp(for: url) {
                NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
            }
        }
        if external && NSDocumentController.shared.documents.isEmpty { NSApp.terminate(nil) }
    }
    // Back in Finder (or opening another file from it): save edits and close.
    func applicationDidResignActive(_ notification: Notification) { saveAndCloseAll() }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard NSDocumentController.shared.documents.contains(where: \.isDocumentEdited) else { return .terminateNow }
        saveAndCloseAll()  // the app quits once the last panel has closed
        return .terminateCancel
    }

    func saveAndCloseAll() {
        for case let doc as Doc in NSDocumentController.shared.documents {
            if doc.isDocumentEdited { doc.saveAndClose(nil) } else { doc.close() }
        }
    }
}

func buildMenu() -> NSMenu {
    // Accessory app: the menu bar isn't shown, but these shortcuts still work.
    func item(_ title: String, _ action: Selector?, _ key: String, _ mods: NSEvent.ModifierFlags = .command, tag: Int = 0) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = mods
        i.tag = tag
        return i
    }
    func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let m = NSMenu(title: title); items.forEach(m.addItem)
        let top = NSMenuItem(); top.submenu = m
        return top
    }
    let main = NSMenu()
    main.addItem(menu("Side Edit", [item("Quit Side Edit", #selector(NSApplication.terminate(_:)), "q")]))
    main.addItem(menu("File", [
        item("Save and Close", #selector(Doc.saveAndClose(_:)), "s"),
        item("Revert to Saved", #selector(NSDocument.revertToSaved(_:)), ""),
        item("Open in Usual App", #selector(Doc.openInBigEditor(_:)), "e"),
        item("Move to Trash", #selector(Doc.moveToTrash(_:)), "\u{8}"),
        .separator(),
        item("Close", #selector(NSWindow.performClose(_:)), "w"),
        item("Close (Esc)", #selector(NSWindow.performClose(_:)), "\u{1b}", []),
    ]))
    main.addItem(menu("Edit", [
        item("Undo", Selector(("undo:")), "z"),
        item("Redo", Selector(("redo:")), "z", [.command, .shift]),
        .separator(),
        item("Cut", #selector(NSText.cut(_:)), "x"),
        item("Copy", #selector(NSText.copy(_:)), "c"),
        item("Paste", #selector(NSText.paste(_:)), "v"),
        item("Select All", #selector(NSText.selectAll(_:)), "a"),
        .separator(),
        item("Find…", #selector(NSTextView.performFindPanelAction(_:)), "f", tag: Int(NSFindPanelAction.showFindPanel.rawValue)),
        item("Find Next", #selector(NSTextView.performFindPanelAction(_:)), "g", tag: Int(NSFindPanelAction.next.rawValue)),
    ]))
    return main
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // never a Dock icon
app.mainMenu = buildMenu()
app.run()
