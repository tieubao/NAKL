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
import AppKit
import UniformTypeIdentifiers

struct ExcludedAppsSettingsView: View {
    @State private var rows: [ExcludedAppRow] = []
    @State private var selection: ExcludedAppRow.ID?

    var body: some View {
        VStack(spacing: 12) {
            Table(rows, selection: $selection) {
                TableColumn(String(localized: "Application")) {
                    Text($0.displayName)
                }
                TableColumn(String(localized: "Bundle ID")) {
                    Text($0.bundleId).font(.system(.body, design: .monospaced))
                }
            }
            .frame(minHeight: 200)

            HStack {
                Button(String(localized: "Add app…")) { pickApp() }
                Button(String(localized: "Remove")) { removeSelected() }
                    .disabled(selection == nil)
            }
        }
        .padding()
        .onAppear { reload() }
    }

    private func reload() {
        let dict = AppData.shared().excludedApps ?? NSMutableDictionary()
        var out: [ExcludedAppRow] = []
        for case let (key as String, value as String) in dict {
            out.append(ExcludedAppRow(bundleId: key, displayName: value))
        }
        rows = out.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK,
           let url = panel.url,
           let bundle = Bundle(url: url),
           let id = bundle.bundleIdentifier {
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            let dict = AppData.shared().excludedApps ?? NSMutableDictionary()
            dict[id] = name
            AppData.shared().excludedApps = dict
            persist()
            reload()
        }
    }

    private func removeSelected() {
        guard let id = selection,
              let row = rows.first(where: { $0.id == id }),
              let dict = AppData.shared().excludedApps else { return }
        dict.removeObject(forKey: row.bundleId)
        AppData.shared().excludedApps = dict
        persist()
        selection = nil
        reload()
    }

    private func persist() {
        let dict = AppData.shared().excludedApps ?? NSMutableDictionary()
        AppData.shared().userPrefs?.set(dict, forKey: NAKL_EXCLUDED_APPS)
    }
}

struct ExcludedAppRow: Identifiable, Hashable {
    var id: String { bundleId }
    let bundleId: String
    let displayName: String
}
