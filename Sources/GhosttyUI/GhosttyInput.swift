import AppKit

/// Keyboard modifiers matching libghostty's `ghostty_input_mods_e` bit layout.
public struct GhosttyKeyMods: OptionSet, Sendable, Equatable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let shift = Self(rawValue: 1 << 0)
    public static let control = Self(rawValue: 1 << 1)
    public static let option = Self(rawValue: 1 << 2)
    public static let command = Self(rawValue: 1 << 3)
    public static let capsLock = Self(rawValue: 1 << 4)
    public static let numericPad = Self(rawValue: 1 << 5)
    public static let rightShift = Self(rawValue: 1 << 6)
    public static let rightControl = Self(rawValue: 1 << 7)
    public static let rightOption = Self(rawValue: 1 << 8)
    public static let rightCommand = Self(rawValue: 1 << 9)
}

enum GhosttyInput {
    // From <IOKit/hidsystem/IOLLEvent.h> / NX_DEVICE* key masks.
    private static let rightShiftMask: UInt = 0x00000004
    private static let rightControlMask: UInt = 0x00002000
    private static let rightOptionMask: UInt = 0x00000040
    private static let rightCommandMask: UInt = 0x00000010

    static func mods(from flags: NSEvent.ModifierFlags) -> GhosttyKeyMods {
        var mods: GhosttyKeyMods = []
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.control) { mods.insert(.control) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.capsLock) { mods.insert(.capsLock) }
        if flags.contains(.numericPad) { mods.insert(.numericPad) }

        let raw = flags.rawValue
        if raw & rightShiftMask != 0 { mods.insert(.rightShift) }
        if raw & rightControlMask != 0 { mods.insert(.rightControl) }
        if raw & rightOptionMask != 0 { mods.insert(.rightOption) }
        if raw & rightCommandMask != 0 { mods.insert(.rightCommand) }
        return mods
    }

    static func mouseButton(fromNSEventButtonNumber number: Int) -> UInt32 {
        switch number {
        case 0: 1 // GHOSTTY_MOUSE_LEFT
        case 1: 2 // GHOSTTY_MOUSE_RIGHT
        case 2: 3 // GHOSTTY_MOUSE_MIDDLE
        case 3: 4
        case 4: 5
        default: 0
        }
    }

    /// Packed scroll modifiers: bit 0 = precision, bits 1...3 = momentum phase.
    static func scrollMods(precision: Bool, momentumPhase: NSEvent.Phase) -> Int32 {
        var value: Int32 = 0
        if precision { value |= 0b1 }
        value |= Int32(momentumBits(momentumPhase)) << 1
        return value
    }

    static func momentumBits(_ phase: NSEvent.Phase) -> UInt8 {
        if phase.contains(.began) { return 1 }
        if phase.contains(.stationary) { return 2 }
        if phase.contains(.changed) { return 3 }
        if phase.contains(.ended) { return 4 }
        if phase.contains(.cancelled) { return 5 }
        if phase.contains(.mayBegin) { return 6 }
        return 0
    }

    static func textForKeyEvent(_ event: NSEvent) -> String? {
        guard let characters = event.characters else { return nil }
        if characters.count == 1, let scalar = characters.unicodeScalars.first {
            if scalar.value < 0x20 {
                return event.characters(byApplyingModifiers: event.modifierFlags.subtracting(.control))
            }
            if (0xF700...0xF8FF).contains(scalar.value) {
                return nil
            }
        }
        return characters
    }
}

enum GhosttyCursor {
    static func nsCursor(for shapeRaw: UInt32) -> NSCursor {
        // Matches `ghostty_action_mouse_shape_e`.
        switch shapeRaw {
        case 3: NSCursor.pointingHand      // pointer
        case 7: NSCursor.crosshair         // crosshair
        case 8, 9: NSCursor.iBeam          // text / vertical text
        case 11: NSCursor.dragCopy         // copy
        case 12: NSCursor.openHand         // move
        case 14: NSCursor.operationNotAllowed
        case 15: NSCursor.openHand         // grab
        case 16: NSCursor.closedHand       // grabbing
        case 18: NSCursor.resizeLeftRight  // col-resize
        case 19: NSCursor.resizeUpDown     // row-resize
        case 28: NSCursor.resizeLeftRight  // ew-resize
        case 29: NSCursor.resizeUpDown     // ns-resize
        default: NSCursor.arrow
        }
    }
}
