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

struct ShortcutsSettingsView: View {
    @State private var rows: [ShortcutRow] = []
    @State private var selection: ShortcutRow.ID?
    @State private var draftShortcut = ""
    @State private var draftText = ""

    var body: some View {
        VStack(spacing: 12) {
            Table(rows, selection: $selection) {
                TableColumn(String(localized: "Shortcut")) { Text($0.shortcut) }
                TableColumn(String(localized: "Expansion")) { Text($0.text) }
            }
            .frame(minHeight: 200)

            HStack(spacing: 8) {
                TextField(String(localized: "shortcut"), text: $draftShortcut)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 140)
                TextField(String(localized: "expansion"), text: $draftText)
                    .textFieldStyle(.roundedBorder)
                Button(String(localized: "Add")) { addRow() }
                    .disabled(draftShortcut.isEmpty || draftText.isEmpty)
                Button(String(localized: "Delete")) { deleteSelected() }
                    .disabled(selection == nil)
            }
        }
        .padding()
        .onAppear { reload() }
    }

    private func reload() {
        let array = AppData.shared().shortcuts ?? NSMutableArray()
        rows = array.compactMap { item -> ShortcutRow? in
            guard let setting = item as? ShortcutSetting else { return nil }
            return ShortcutRow(shortcut: setting.shortcut ?? "",
                               text: setting.text ?? "")
        }
    }

    private func addRow() {
        let setting = ShortcutSetting()
        setting.shortcut = draftShortcut
        setting.text = draftText

        let arr = AppData.shared().shortcuts ?? NSMutableArray()
        arr.add(setting)
        AppData.shared().shortcuts = arr

        let dict = AppData.shared().shortcutDictionary ?? NSMutableDictionary()
        dict[draftShortcut] = draftText
        AppData.shared().shortcutDictionary = dict

        ShortcutSettingsPersistence.save()
        draftShortcut = ""
        draftText = ""
        reload()
    }

    private func deleteSelected() {
        guard let id = selection,
              let row = rows.first(where: { $0.id == id }),
              let arr = AppData.shared().shortcuts else { return }
        let mutable = arr
        for i in stride(from: mutable.count - 1, through: 0, by: -1) {
            if let s = mutable[i] as? ShortcutSetting,
               s.shortcut == row.shortcut, s.text == row.text {
                mutable.removeObject(at: i)
            }
        }
        AppData.shared().shortcuts = mutable
        AppData.shared().shortcutDictionary?.removeObject(forKey: row.shortcut)
        ShortcutSettingsPersistence.save()
        selection = nil
        reload()
    }
}

struct ShortcutRow: Identifiable, Hashable {
    var id: String { shortcut + "→" + text }
    let shortcut: String
    let text: String
}

enum ShortcutSettingsPersistence {
    static func save() {
        guard let arr = AppData.shared().shortcuts as? [Any] else { return }
        guard let supportDir = FileManager.default.applicationSupportDirectory() else { return }
        let url = URL(fileURLWithPath: supportDir).appendingPathComponent("shortcuts.setting")

        do {
            let inner = try NSKeyedArchiver.archivedData(
                withRootObject: arr, requiringSecureCoding: false)
            let outer = try NSKeyedArchiver.archivedData(
                withRootObject: inner, requiringSecureCoding: false)
            try outer.write(to: url, options: .atomic)
        } catch {
            NSLog("[Monke] failed to save shortcuts.setting: %@", error.localizedDescription)
        }
    }
}
