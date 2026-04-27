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

@MainActor
final class AppLocaleTests: XCTestCase {
    private static let preferredKey = "NAKLPreferredLanguage"
    private static let appleLanguagesKey = "AppleLanguages"

    private var savedAppleLanguages: Any?

    override func setUp() {
        super.setUp()
        savedAppleLanguages = UserDefaults.standard.object(forKey: Self.appleLanguagesKey)
        UserDefaults.standard.removeObject(forKey: Self.preferredKey)
        UserDefaults.standard.removeObject(forKey: Self.appleLanguagesKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: Self.preferredKey)
        if let saved = savedAppleLanguages {
            UserDefaults.standard.set(saved, forKey: Self.appleLanguagesKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.appleLanguagesKey)
        }
        super.tearDown()
    }

    func testEmptyPreferenceFallsBackToCurrentLocale() {
        UserDefaults.standard.removeObject(forKey: Self.preferredKey)
        let locale = AppLocale().locale
        XCTAssertEqual(locale.identifier, Locale.current.identifier)
    }

    func testEnglishPreferenceProducesEnLocale() {
        UserDefaults.standard.set("en", forKey: Self.preferredKey)
        let locale = AppLocale().locale
        XCTAssertEqual(locale.identifier, "en")
    }

    func testVietnamesePreferenceProducesViLocale() {
        UserDefaults.standard.set("vi", forKey: Self.preferredKey)
        let locale = AppLocale().locale
        XCTAssertEqual(locale.identifier, "vi")
    }

    func testSetPreferredViUpdatesBothDefaults() {
        let appLocale = AppLocale()
        appLocale.setPreferred("vi")

        XCTAssertEqual(
            UserDefaults.standard.string(forKey: Self.preferredKey),
            "vi"
        )
        XCTAssertEqual(
            UserDefaults.standard.array(forKey: Self.appleLanguagesKey) as? [String],
            ["vi"]
        )
        XCTAssertEqual(appLocale.locale.identifier, "vi")
    }

    func testSetPreferredEnUpdatesAppleLanguages() {
        let appLocale = AppLocale()
        appLocale.setPreferred("en")

        XCTAssertEqual(
            UserDefaults.standard.array(forKey: Self.appleLanguagesKey) as? [String],
            ["en"]
        )
        XCTAssertEqual(appLocale.locale.identifier, "en")
    }

    func testSetPreferredEmptyRemovesOurOverride() {
        let appLocale = AppLocale()
        appLocale.setPreferred("vi")
        XCTAssertEqual(
            UserDefaults.standard.array(forKey: Self.appleLanguagesKey) as? [String],
            ["vi"]
        )

        appLocale.setPreferred("")

        XCTAssertNil(UserDefaults.standard.string(forKey: Self.preferredKey))
        // After removal AppleLanguages may inherit a system-wide default; we
        // only assert that our ["vi"] override was cleared.
        let after = UserDefaults.standard.array(forKey: Self.appleLanguagesKey) as? [String]
        XCTAssertNotEqual(after, ["vi"])
    }
}
