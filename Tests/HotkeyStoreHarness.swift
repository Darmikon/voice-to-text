import Carbon.HIToolbox
import Foundation

struct StoreHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw StoreHarnessFailure(description: message)
    }
}

@main
struct HotkeyStoreHarness {
    static func main() async throws {
        let defaults = UserDefaults.standard
        let bindingKey = "hotkey.binding.v1"
        let modeKey = "hotkey.recordingMode.v1"
        let previousBinding = defaults.data(forKey: bindingKey)
        let previousMode = defaults.string(forKey: modeKey)
        let previousSendOnReturn = defaults.object(forKey: "review.sendOnReturn.v1")
        let previousSendShortcut = defaults.data(forKey: "review.sendShortcut.v1")

        defer {
            if let previousBinding {
                defaults.set(previousBinding, forKey: bindingKey)
            } else {
                defaults.removeObject(forKey: bindingKey)
            }

            if let previousMode {
                defaults.set(previousMode, forKey: modeKey)
            } else {
                defaults.removeObject(forKey: modeKey)
            }

            if let previousSendOnReturn {
                defaults.set(previousSendOnReturn, forKey: "review.sendOnReturn.v1")
            } else {
                defaults.removeObject(forKey: "review.sendOnReturn.v1")
            }
            if let previousSendShortcut {
                defaults.set(previousSendShortcut, forKey: "review.sendShortcut.v1")
            } else {
                defaults.removeObject(forKey: "review.sendShortcut.v1")
            }
        }

        defaults.removeObject(forKey: modeKey)

        try await MainActor.run {
            let store = HotkeyStore.shared
            try expect(store.mode == .toggle, "missing mode preserves existing toggle behavior")

            store.updateMode(to: .toggle)
            try expect(store.mode == .toggle, "mode updates in memory")

            store.updateMode(to: .hold)
            try expect(store.mode == .hold, "mode can switch back to hold")
            try expect(defaults.string(forKey: modeKey) == "hold", "hold mode persists to defaults")

            let rightControl = HotkeyBinding.rightControlBinding
            store.update(to: rightControl)
            let saved = defaults.data(forKey: bindingKey)
            try expect(saved != nil, "binding persists to defaults")
            let decoded = try JSONDecoder().decode(HotkeyBinding.self, from: saved ?? Data())
            try expect(decoded == rightControl, "persisted binding decodes as right Control")

            let sendOnReturnKey = "review.sendOnReturn.v1"
            let sendShortcutKey = "review.sendShortcut.v1"
            defaults.removeObject(forKey: sendOnReturnKey)
            defaults.removeObject(forKey: sendShortcutKey)

            try expect(store.sendOnReturn == true, "send-on-return defaults to true")
            try expect(store.sendShortcut == .commandReturnBinding, "send shortcut defaults to Cmd+Return")

            store.updateSendOnReturn(to: false)
            try expect(store.sendOnReturn == false, "send-on-return updates in memory")
            try expect(defaults.object(forKey: sendOnReturnKey) as? Bool == false, "send-on-return persists")

            let custom = HotkeyBinding(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(cmdKey), keyLabel: "D")
            store.updateSendShortcut(to: custom)
            let savedSend = defaults.data(forKey: sendShortcutKey)
            try expect(savedSend != nil, "send shortcut persists to defaults")
            let decodedSend = try JSONDecoder().decode(HotkeyBinding.self, from: savedSend ?? Data())
            try expect(decodedSend == custom, "persisted send shortcut decodes back")

            defaults.removeObject(forKey: sendOnReturnKey)
            defaults.removeObject(forKey: sendShortcutKey)
        }

        print("Hotkey store harness passed")
    }
}
