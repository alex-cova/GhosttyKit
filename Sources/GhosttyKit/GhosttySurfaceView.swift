@preconcurrency import AppKit
import Foundation

#if GHOSTTYKIT_HAS_KIT
import GhosttyKitC
#endif

/// AppKit surface that hosts libghostty's Metal renderer.
@MainActor
final class GhosttySurfaceView: NSView, GhosttySurfaceAttaching {
    weak var session: GhosttySession?
    let configuration: GhosttySurfaceConfiguration

    #if GHOSTTYKIT_HAS_KIT
    nonisolated(unsafe) private var surface: ghostty_surface_t?
    #endif

    private var trackingArea: NSTrackingArea?
    private var markedText = NSMutableAttributedString()
    var isMouseHidden = false
    private var mouseShapeRaw: UInt32 = 0
    nonisolated(unsafe) private var eventMonitor: Any?

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }
    override var canBecomeKeyView: Bool { true }

    init(session: GhosttySession, configuration: GhosttySurfaceConfiguration) {
        self.session = session
        self.configuration = configuration
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        #if GHOSTTYKIT_HAS_KIT
        if let surface {
            let handle = surface
            Task { @MainActor in
                ghostty_surface_free(handle)
            }
        }
        #endif
    }

    func teardown() {
        session?.detach(self)
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        #if GHOSTTYKIT_HAS_KIT
        GhosttyRuntime.shared.forgetSurface(self)
        if let surface {
            ghostty_surface_free(surface)
            self.surface = nil
        }
        #endif
    }

    private func setup() {
        #if GHOSTTYKIT_HAS_KIT
        do {
            let created = try GhosttyRuntime.shared.makeSurface(view: self, configuration: configuration)
            surface = created
            session?.attach(self)
            session?.lastError = nil
        } catch let error as GhosttyError {
            session?.lastError = error
        } catch {
            session?.lastError = .runtimeFailed(error.localizedDescription)
        }
        #else
        session?.lastError = .kitMissing
        #endif

        updateTrackingAreas()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyUp]) { [weak self] event in
            self?.handleMonitoredKeyUp(event) ?? event
        }
    }

    func sendText(_ text: String) {
        #if GHOSTTYKIT_HAS_KIT
        guard let surface, !text.isEmpty else { return }
        text.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(text.utf8.count))
        }
        #endif
    }

    func requestClose() {
        #if GHOSTTYKIT_HAS_KIT
        guard let surface else { return }
        ghostty_surface_request_close(surface)
        #endif
    }

    func applyMouseShape(_ raw: UInt32) {
        mouseShapeRaw = raw
        window?.invalidateCursorRects(for: self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        if isMouseHidden {
            addCursorRect(bounds, cursor: .arrow)
            NSCursor.setHiddenUntilMouseMoves(true)
            return
        }
        addCursorRect(bounds, cursor: GhosttyCursor.nsCursor(for: mouseShapeRaw))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncSurfaceMetrics()
        #if GHOSTTYKIT_HAS_KIT
        GhosttyRuntime.shared.applyColorScheme()
        if let surface {
            ghostty_surface_set_focus(surface, window?.firstResponder === self)
        }
        #endif
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncSurfaceMetrics()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        syncSurfaceMetrics()
    }

    private func syncSurfaceMetrics() {
        #if GHOSTTYKIT_HAS_KIT
        guard let surface, bounds.width > 0, bounds.height > 0 else { return }
        if let window {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.contentsScale = window.backingScaleFactor
            CATransaction.commit()
        }
        let fb = convertToBacking(bounds)
        let xScale = fb.width / max(bounds.width, 1)
        let yScale = fb.height / max(bounds.height, 1)
        ghostty_surface_set_content_scale(surface, xScale, yScale)
        ghostty_surface_set_size(surface, UInt32(fb.width.rounded()), UInt32(fb.height.rounded()))
        #endif
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        #if GHOSTTYKIT_HAS_KIT
        if let surface { ghostty_surface_set_focus(surface, true) }
        #endif
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        #if GHOSTTYKIT_HAS_KIT
        if let surface { ghostty_surface_set_focus(surface, false) }
        #endif
        return ok
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) { sendMouseButton(event, pressed: true) }
    override func mouseUp(with event: NSEvent) { sendMouseButton(event, pressed: false) }
    override func rightMouseDown(with event: NSEvent) { sendMouseButton(event, pressed: true) }
    override func rightMouseUp(with event: NSEvent) { sendMouseButton(event, pressed: false) }
    override func otherMouseDown(with event: NSEvent) { sendMouseButton(event, pressed: true) }
    override func otherMouseUp(with event: NSEvent) { sendMouseButton(event, pressed: false) }
    override func mouseDragged(with event: NSEvent) { sendMouseMoved(event) }
    override func rightMouseDragged(with event: NSEvent) { sendMouseMoved(event) }
    override func otherMouseDragged(with event: NSEvent) { sendMouseMoved(event) }
    override func mouseMoved(with event: NSEvent) { sendMouseMoved(event) }

    override func mouseEntered(with event: NSEvent) {
        sendMouseMoved(event)
    }

    override func mouseExited(with event: NSEvent) {
        #if GHOSTTYKIT_HAS_KIT
        guard let surface else { return }
        let mods = GhosttyInput.mods(from: event.modifierFlags)
        ghostty_surface_mouse_pos(surface, -1, -1, ghostty_input_mods_e(mods.rawValue))
        #endif
    }

    override func scrollWheel(with event: NSEvent) {
        #if GHOSTTYKIT_HAS_KIT
        guard let surface else { return }
        var x = event.scrollingDeltaX
        var y = event.scrollingDeltaY
        if event.hasPreciseScrollingDeltas {
            x *= 2
            y *= 2
        }
        ghostty_surface_mouse_scroll(
            surface,
            x,
            y,
            GhosttyInput.scrollMods(precision: event.hasPreciseScrollingDeltas, momentumPhase: event.momentumPhase)
        )
        #endif
    }

    private func sendMouseButton(_ event: NSEvent, pressed: Bool) {
        window?.makeFirstResponder(self)
        #if GHOSTTYKIT_HAS_KIT
        guard let surface else { return }
        sendMouseMoved(event)
        let mods = GhosttyInput.mods(from: event.modifierFlags)
        ghostty_surface_mouse_button(
            surface,
            pressed ? GHOSTTY_MOUSE_PRESS : GHOSTTY_MOUSE_RELEASE,
            ghostty_input_mouse_button_e(GhosttyInput.mouseButton(fromNSEventButtonNumber: event.buttonNumber)),
            ghostty_input_mods_e(mods.rawValue)
        )
        #endif
    }

    private func sendMouseMoved(_ event: NSEvent) {
        #if GHOSTTYKIT_HAS_KIT
        guard let surface else { return }
        let pos = convert(event.locationInWindow, from: nil)
        let mods = GhosttyInput.mods(from: event.modifierFlags)
        ghostty_surface_mouse_pos(
            surface,
            pos.x,
            bounds.height - pos.y,
            ghostty_input_mods_e(mods.rawValue)
        )
        #endif
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        if hasMarkedText() {
            interpretKeyEvents([event])
            return
        }
        if sendKey(event, actionRepeat: event.isARepeat) == false {
            interpretKeyEvents([event])
        }
    }

    override func keyUp(with event: NSEvent) {
        _ = sendKey(event, isRelease: true)
    }

    override func flagsChanged(with event: NSEvent) {
        _ = sendKey(event)
    }

    private func handleMonitoredKeyUp(_ event: NSEvent) -> NSEvent? {
        if event.modifierFlags.contains(.command) {
            _ = sendKey(event, isRelease: true)
        }
        return event
    }

    @discardableResult
    private func sendKey(_ event: NSEvent, isRelease: Bool = false, actionRepeat: Bool = false) -> Bool {
        #if GHOSTTYKIT_HAS_KIT
        guard let surface else { return false }
        let action: ghostty_input_action_e = if isRelease {
            GHOSTTY_ACTION_RELEASE
        } else if actionRepeat {
            GHOSTTY_ACTION_REPEAT
        } else {
            GHOSTTY_ACTION_PRESS
        }

        let translation = ghostty_surface_key_translation_mods(
            surface,
            ghostty_input_mods_e(GhosttyInput.mods(from: event.modifierFlags).rawValue)
        )
        var translationFlags = event.modifierFlags
        let translated = GhosttyKeyMods(rawValue: translation.rawValue)
        for (ns, ghost) in [
            (NSEvent.ModifierFlags.shift, GhosttyKeyMods.shift),
            (.control, .control),
            (.option, .option),
            (.command, .command)
        ] as [(NSEvent.ModifierFlags, GhosttyKeyMods)] {
            if translated.contains(ghost) {
                translationFlags.insert(ns)
            } else {
                translationFlags.remove(ns)
            }
        }

        var key = ghostty_input_key_s()
        key.action = action
        key.keycode = UInt32(event.keyCode)
        key.mods = ghostty_input_mods_e(GhosttyInput.mods(from: event.modifierFlags).rawValue)
        key.consumed_mods = ghostty_input_mods_e(
            GhosttyInput.mods(from: translationFlags.subtracting([.control, .command])).rawValue
        )
        key.composing = false
        if event.type == .keyDown || event.type == .keyUp,
           let chars = event.characters(byApplyingModifiers: []),
           let scalar = chars.unicodeScalars.first {
            key.unshifted_codepoint = scalar.value
        }

        if let text = GhosttyInput.textForKeyEvent(event), !isRelease,
           let first = text.unicodeScalars.first, first.value >= 0x20 {
            return text.withCString { ptr in
                key.text = ptr
                return ghostty_surface_key(surface, key)
            }
        }
        return ghostty_surface_key(surface, key)
        #else
        return false
        #endif
    }

    @objc func copy(_ sender: Any?) {
        #if GHOSTTYKIT_HAS_KIT
        guard let surface, ghostty_surface_has_selection(surface) else { return }
        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text) else { return }
        defer { ghostty_surface_free_text(surface, &text) }
        if let ptr = text.text, text.text_len > 0 {
            let value = String(bytes: UnsafeBufferPointer(start: ptr, count: Int(text.text_len)).map { UInt8(bitPattern: $0) }, encoding: .utf8)
            if let value {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            }
        }
        #endif
    }

    @objc func paste(_ sender: Any?) {
        if let string = NSPasteboard.general.string(forType: .string) {
            sendText(string)
        }
    }

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        #if GHOSTTYKIT_HAS_KIT
        if item.action == #selector(copy(_:)) {
            return surface.map { ghostty_surface_has_selection($0) } ?? false
        }
        #endif
        if item.action == #selector(paste(_:)) {
            return NSPasteboard.general.string(forType: .string) != nil
        }
        return true
    }

    #if GHOSTTYKIT_HAS_KIT
    func readClipboard(location: ghostty_clipboard_e, state: UnsafeMutableRawPointer?) {
        guard let surface else { return }
        let pasteboard: NSPasteboard = location == GHOSTTY_CLIPBOARD_SELECTION
            ? NSPasteboard(name: .find)
            : .general
        let string = pasteboard.string(forType: .string) ?? ""
        completeClipboardRequest(surface: surface, data: string, state: state)
    }

    func confirmReadClipboard(
        string: UnsafePointer<CChar>?,
        state: UnsafeMutableRawPointer?,
        request: ghostty_clipboard_request_e
    ) {
        guard let surface else { return }
        _ = request

        guard let string else {
            completeClipboardRequest(surface: surface, data: "", state: state, confirmed: false)
            return
        }

        let value = String(cString: string)
        let allowed = configuration.allowsUnconfirmedClipboardWrites
            || session?.onConfirmClipboardWrite?(value) == true
        guard allowed else {
            completeClipboardRequest(surface: surface, data: "", state: state, confirmed: false)
            return
        }

        completeClipboardRequest(surface: surface, data: value, state: state, confirmed: true)
    }

    func writeClipboard(
        location: ghostty_clipboard_e,
        content: UnsafePointer<ghostty_clipboard_content_s>?,
        len: Int,
        confirm: Bool
    ) {
        guard let content, len > 0 else { return }
        let pasteboard: NSPasteboard = location == GHOSTTY_CLIPBOARD_SELECTION
            ? NSPasteboard(name: .find)
            : .general

        var textPlain: String?
        for index in 0..<len {
            let item = content[index]
            guard let mimePtr = item.mime, let dataPtr = item.data else { continue }
            guard String(cString: mimePtr) == "text/plain" else { continue }
            textPlain = String(cString: dataPtr)
            break
        }
        guard let string = textPlain else { return }

        if confirm {
            let allowed = configuration.allowsUnconfirmedClipboardWrites
                || session?.onConfirmClipboardWrite?(string) == true
            guard allowed else { return }
        }

        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    private func completeClipboardRequest(
        surface: ghostty_surface_t,
        data: String,
        state: UnsafeMutableRawPointer?,
        confirmed: Bool = false
    ) {
        data.withCString { ptr in
            ghostty_surface_complete_clipboard_request(surface, ptr, state, confirmed)
        }
    }
    #endif
}

extension GhosttySurfaceView: @preconcurrency NSTextInputClient, NSUserInterfaceValidations {
    func hasMarkedText() -> Bool {
        markedText.length > 0
    }

    func markedRange() -> NSRange {
        NSRange(location: 0, length: markedText.length)
    }

    func selectedRange() -> NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let attributed: NSAttributedString = if let attributed = string as? NSAttributedString {
            attributed
        } else if let text = string as? String {
            NSAttributedString(string: text)
        } else {
            NSAttributedString()
        }
        markedText = NSMutableAttributedString(attributedString: attributed)
        #if GHOSTTYKIT_HAS_KIT
        if let surface {
            let value = markedText.string
            value.withCString { ptr in
                ghostty_surface_preedit(surface, ptr, UInt(value.utf8.count))
            }
        }
        #endif
    }

    func unmarkText() {
        markedText = NSMutableAttributedString()
        #if GHOSTTYKIT_HAS_KIT
        if let surface {
            ghostty_surface_preedit(surface, "", 0)
        }
        #endif
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        nil
    }

    func characterIndex(for point: NSPoint) -> Int { NSNotFound }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        #if GHOSTTYKIT_HAS_KIT
        guard let surface, let window else { return .zero }
        var x: Double = 0
        var y: Double = 0
        var width: Double = 0
        var height: Double = 0
        ghostty_surface_ime_point(surface, &x, &y, &width, &height)
        let viewRect = NSRect(x: x, y: bounds.height - y - height, width: max(width, 1), height: max(height, 1))
        let windowRect = convert(viewRect, to: nil)
        return window.convertToScreen(windowRect)
        #else
        .zero
        #endif
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        unmarkText()
        let text: String = if let attributed = string as? NSAttributedString {
            attributed.string
        } else if let value = string as? String {
            value
        } else {
            ""
        }
        guard !text.isEmpty else { return }
        sendText(text)
    }

    override func doCommand(by selector: Selector) {
        if selector == #selector(insertNewline(_:)) {
            sendText("\n")
        } else if selector == #selector(insertTab(_:)) {
            sendText("\t")
        } else if selector == #selector(deleteBackward(_:)) {
            sendText("\u{7f}")
        }
    }
}
