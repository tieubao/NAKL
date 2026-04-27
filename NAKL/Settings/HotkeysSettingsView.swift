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

struct HotkeysSettingsView: View {
    @State private var togglePrintable: String = "—"
    @State private var switchPrintable: String = "—"

    var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: "Toggle on / off")) {
                    HotkeyRecorderField(printable: $togglePrintable,
                                        defaultsKey: NAKL_TOGGLE_HOTKEY)
                }
                LabeledContent(String(localized: "Switch VNI ↔ Telex")) {
                    HotkeyRecorderField(printable: $switchPrintable,
                                        defaultsKey: NAKL_SWITCH_METHOD_HOTKEY)
                }
            } footer: {
                Text(String(localized: "Click a field, then press the desired key combination. Changes apply on next app launch."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { refreshPrintables() }
    }

    private func refreshPrintables() {
        togglePrintable = HotkeyPlistFormat.printable(forKey: NAKL_TOGGLE_HOTKEY) ?? "—"
        switchPrintable = HotkeyPlistFormat.printable(forKey: NAKL_SWITCH_METHOD_HOTKEY) ?? "—"
    }
}

struct HotkeyRecorderField: NSViewRepresentable {
    @Binding var printable: String
    let defaultsKey: String

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let view = HotkeyRecorderNSView(defaultsKey: defaultsKey)
        view.onChange = { newPrintable in
            printable = newPrintable
        }
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderNSView, context: Context) {
        nsView.refreshFromDefaults()
    }
}
