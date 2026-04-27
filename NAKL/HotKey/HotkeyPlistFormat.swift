/*******************************************************************************
 * Copyright (c) 2026
 * This file is part of Monke (formerly NAKL).
 *
 * Monke is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Monke is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Monke.  If not, see <http://www.gnu.org/licenses/>.
 ******************************************************************************/

import AppKit
import Carbon.HIToolbox

/// Reads / writes the legacy PTKeyCombo plist representation (`{characters,
/// keyCode, modifiers}`) used by NAKL_TOGGLE_HOTKEY / NAKL_SWITCH_METHOD_HOTKEY.
/// The on-disk format is preserved so the existing C/ObjC hot path that reads
/// `[AppData sharedAppData].toggleCombo` continues to work without changes.
enum HotkeyPlistFormat {
    static func printable(forKey key: String) -> String? {
        guard let dict = UserDefaults.standard.dictionary(forKey: key),
              let keyCode = dict["keyCode"] as? Int else { return nil }
        let cocoaMods = cocoaModifiersFromCarbon(carbon: dict["modifiers"] as? Int ?? 0)
        let symbol = symbolForKeyCode(keyCode)
        return printableModifiers(cocoaMods) + symbol
    }

    static func write(keyCode: Int,
                      cocoaModifiers: NSEvent.ModifierFlags,
                      forKey key: String) {
        let carbonMods = carbonModifiersFromCocoa(cocoaModifiers)
        let dict: [String: Any] = [
            "keyCode": keyCode,
            "modifiers": carbonMods,
            "characters": charactersForKeyCode(keyCode) ?? "",
        ]
        UserDefaults.standard.set(dict, forKey: key)
    }

    private static func charactersForKeyCode(_ keyCode: Int) -> String? {
        let layout = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
        guard let layoutData = TISGetInputSourceProperty(
                layout, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = unsafeBitCast(layoutData, to: CFData.self) as Data
        return data.withUnsafeBytes { (rawBuf: UnsafeRawBufferPointer) -> String? in
            let layoutPtr = rawBuf.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self)
            guard let layoutPtr else { return nil }
            var deadKeyState: UInt32 = 0
            var actualLength = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layoutPtr,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &actualLength,
                &chars)
            if status != noErr || actualLength == 0 { return nil }
            return String(utf16CodeUnits: chars, count: actualLength)
        }
    }

    private static func cocoaModifiersFromCarbon(carbon: Int) -> NSEvent.ModifierFlags {
        var out: NSEvent.ModifierFlags = []
        if carbon & cmdKey       != 0 { out.insert(.command) }
        if carbon & optionKey    != 0 { out.insert(.option) }
        if carbon & controlKey   != 0 { out.insert(.control) }
        if carbon & shiftKey     != 0 { out.insert(.shift) }
        return out
    }

    private static func carbonModifiersFromCocoa(_ flags: NSEvent.ModifierFlags) -> Int {
        var out = 0
        if flags.contains(.command)   { out |= cmdKey }
        if flags.contains(.option)    { out |= optionKey }
        if flags.contains(.control)   { out |= controlKey }
        if flags.contains(.shift)     { out |= shiftKey }
        return out
    }

    private static func printableModifiers(_ flags: NSEvent.ModifierFlags) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option)  { s += "⌥" }
        if flags.contains(.shift)   { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s
    }

    private static func symbolForKeyCode(_ keyCode: Int) -> String {
        switch keyCode {
        case 36:  return "↩"
        case 48:  return "⇥"
        case 49:  return "Space"
        case 51:  return "⌫"
        case 53:  return "⎋"
        case 117: return "⌦"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            if let chars = charactersForKeyCode(keyCode), !chars.isEmpty {
                return chars.uppercased()
            }
            return "Key \(keyCode)"
        }
    }
}
