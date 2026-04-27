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
import SwiftUI

/// Hosts the SwiftUI Settings tree inside an NSWindow that the legacy ObjC
/// AppDelegate can present. Replaces PreferencesController + Preferences.xib
/// without disturbing the menu-bar / event-tap pipeline.
@MainActor
@objcMembers
final class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController()

    private convenience init() {
        let host = NSHostingController(rootView: SettingsRoot())
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.title = String(localized: "Monke Preferences")
        window.titleVisibility = .visible
        window.setContentSize(NSSize(width: 540, height: 360))
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }

    @objc func presentFromMenu(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(sender)
        window?.center()
    }
}
