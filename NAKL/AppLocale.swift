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

import Foundation
import Combine

/// Runtime app locale. Reads `NAKLPreferredLanguage` from defaults and
/// publishes a Locale that the SwiftUI tree binds via `.environment(\.locale,
/// ...)`. Changing the picker re-renders the open Settings window without an
/// app relaunch.
@MainActor
final class AppLocale: ObservableObject {
    static let shared = AppLocale()

    @Published private(set) var locale: Locale = .current

    init() {
        recompute()
    }

    func setPreferred(_ tag: String) {
        let defaults = UserDefaults.standard
        if tag.isEmpty {
            defaults.removeObject(forKey: "NAKLPreferredLanguage")
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set(tag, forKey: "NAKLPreferredLanguage")
            defaults.set([tag], forKey: "AppleLanguages")
        }
        recompute()
    }

    private func recompute() {
        let stored = UserDefaults.standard.string(forKey: "NAKLPreferredLanguage") ?? ""
        switch stored {
        case "en": locale = Locale(identifier: "en")
        case "vi": locale = Locale(identifier: "vi")
        default:   locale = .current
        }
    }
}
