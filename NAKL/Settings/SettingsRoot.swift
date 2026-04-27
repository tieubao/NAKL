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

import SwiftUI

struct SettingsRoot: View {
    @State private var locale = AppLocale.shared

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }

            ShortcutsSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "text.cursor") }

            ExcludedAppsSettingsView()
                .tabItem { Label("Excluded Apps", systemImage: "app.badge.checkmark") }

            HotkeysSettingsView()
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
        }
        .frame(minWidth: 540, minHeight: 360)
        .environment(\.locale, locale.locale)
    }
}
