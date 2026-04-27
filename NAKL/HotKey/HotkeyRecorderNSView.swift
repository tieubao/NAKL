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

@MainActor
final class HotkeyRecorderNSView: NSView {
    private let label = NSTextField(labelWithString: "—")
    private let recordButton = NSButton(title: "Record",
                                        target: nil,
                                        action: nil)
    private var isRecording = false
    private let defaultsKey: String
    var onChange: ((String) -> Void)?

    init(defaultsKey: String) {
        self.defaultsKey = defaultsKey
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.monospacedSystemFont(
            ofSize: NSFont.systemFontSize, weight: .regular)
        label.alignment = .right

        recordButton.translatesAutoresizingMaskIntoConstraints = false
        recordButton.target = self
        recordButton.action = #selector(toggleRecording)
        recordButton.bezelStyle = .rounded

        addSubview(label)
        addSubview(recordButton)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            recordButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            recordButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(
                lessThanOrEqualTo: recordButton.leadingAnchor, constant: -8),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
        ])

        refreshFromDefaults()
    }

    func refreshFromDefaults() {
        label.stringValue = HotkeyPlistFormat.printable(forKey: defaultsKey) ?? "—"
    }

    @objc private func toggleRecording() {
        isRecording.toggle()
        if isRecording {
            recordButton.title = "Cancel"
            label.stringValue = "Press a key combination…"
            window?.makeFirstResponder(self)
        } else {
            recordButton.title = "Record"
            refreshFromDefaults()
        }
    }

    override var acceptsFirstResponder: Bool { isRecording }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.isEmpty {
            NSSound.beep()
            return
        }
        HotkeyPlistFormat.write(keyCode: Int(event.keyCode),
                                cocoaModifiers: modifiers,
                                forKey: defaultsKey)
        let printable = HotkeyPlistFormat.printable(forKey: defaultsKey) ?? "—"
        label.stringValue = printable
        onChange?(printable)
        isRecording = false
        recordButton.title = "Record"
    }
}
