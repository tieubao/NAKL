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

import XCTest
import AppKit
import Carbon.HIToolbox

final class HotkeyFormatTests: XCTestCase {
    private let testKey = "MonkeUnitTest_HotkeyFormat"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: testKey)
        super.tearDown()
    }

    func testPrintableReturnsNilForMissingKey() {
        UserDefaults.standard.removeObject(forKey: testKey)
        XCTAssertNil(HotkeyPlistFormat.printable(forKey: testKey))
    }

    func testWriteThenPrintableRoundTrips() {
        HotkeyPlistFormat.write(keyCode: 9,
                                cocoaModifiers: [.control, .option],
                                forKey: testKey)
        XCTAssertEqual(HotkeyPlistFormat.printable(forKey: testKey), "⌃⌥V")
    }

    func testPrintableModifierOrderMatchesAppleConvention() {
        HotkeyPlistFormat.write(keyCode: 9,
                                cocoaModifiers: [.command, .control, .shift, .option],
                                forKey: testKey)
        // Apple's HIG modifier order is ⌃⌥⇧⌘.
        XCTAssertEqual(HotkeyPlistFormat.printable(forKey: testKey), "⌃⌥⇧⌘V")
    }

    func testPrintableUsesSymbolForSpaceKey() {
        HotkeyPlistFormat.write(keyCode: 49,
                                cocoaModifiers: [.control],
                                forKey: testKey)
        XCTAssertEqual(HotkeyPlistFormat.printable(forKey: testKey), "⌃Space")
    }

    func testPrintableUsesSymbolForArrowKey() {
        HotkeyPlistFormat.write(keyCode: 123,
                                cocoaModifiers: [.command],
                                forKey: testKey)
        XCTAssertEqual(HotkeyPlistFormat.printable(forKey: testKey), "⌘←")
    }

    func testWritePersistsCarbonModifierBitmask() {
        HotkeyPlistFormat.write(keyCode: 9,
                                cocoaModifiers: [.command, .option],
                                forKey: testKey)
        let dict = UserDefaults.standard.dictionary(forKey: testKey)
        XCTAssertNotNil(dict)
        let mods = (dict?["modifiers"] as? Int) ?? 0
        XCTAssertEqual(mods & cmdKey,    cmdKey)
        XCTAssertEqual(mods & optionKey, optionKey)
        XCTAssertEqual(mods & shiftKey,  0)
        XCTAssertEqual(mods & controlKey, 0)
    }

    func testWritePersistsKeyCode() {
        HotkeyPlistFormat.write(keyCode: 49,
                                cocoaModifiers: [.command],
                                forKey: testKey)
        let dict = UserDefaults.standard.dictionary(forKey: testKey)
        XCTAssertEqual(dict?["keyCode"] as? Int, 49)
    }

    func testLegacyPlistFormatStillReadable() {
        // Simulate the on-disk format that PTKeyCombo (the deleted Carbon
        // wrapper) writes: {characters, keyCode, modifiers}. Monke's
        // AppData.loadHotKeys reads this format; HotkeyPlistFormat must be
        // backwards-compatible with it.
        UserDefaults.standard.set([
            "characters": "v",
            "keyCode": 9,
            "modifiers": cmdKey | optionKey,
        ], forKey: testKey)
        XCTAssertEqual(HotkeyPlistFormat.printable(forKey: testKey), "⌥⌘V")
    }
}
