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
import ServiceManagement

struct GeneralSettingsView: View {
    @AppStorage("NAKLPreferredLanguage") private var preferredLanguage: String = ""
    @AppStorage(NAKL_LOAD_AT_LOGIN) private var loadAtLogin: Bool = false
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "Language"), selection: $preferredLanguage) {
                    Text(String(localized: "System")).tag("")
                    Text(verbatim: "English").tag("en")
                    Text(verbatim: "Tiếng Việt").tag("vi")
                }
                .onChange(of: preferredLanguage) { _, newValue in
                    AppLocale.shared.setPreferred(newValue)
                }
            } header: {
                Text(String(localized: "Appearance"))
            }

            Section {
                Toggle(String(localized: "Load Monke when I log in"),
                       isOn: Binding(
                           get: { SMAppService.mainApp.status == .enabled },
                           set: { newValue in
                               do {
                                   if newValue {
                                       try SMAppService.mainApp.register()
                                   } else {
                                       try SMAppService.mainApp.unregister()
                                   }
                                   loadAtLogin = newValue
                                   loginItemError = nil
                               } catch {
                                   loginItemError = error.localizedDescription
                               }
                           }
                       ))

                if let err = loginItemError {
                    Text(err)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            } header: {
                Text(String(localized: "Startup"))
            }

            Section {
                LabeledContent(String(localized: "Version"), value: appVersionString())
                LabeledContent(String(localized: "Bundle"),
                               value: Bundle.main.bundleIdentifier ?? "—")
            } header: {
                Text(String(localized: "About"))
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func appVersionString() -> String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }
}
