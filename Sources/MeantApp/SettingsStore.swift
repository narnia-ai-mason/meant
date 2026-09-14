import Foundation
import MeantCore

@MainActor
final class SettingsStore: ObservableObject {
  static let shared = SettingsStore()

  @Published var hotkey: HotkeyBinding {
    didSet { persistHotkey() }
  }

  private init() {
    if let data = UserDefaults.standard.data(forKey: Keys.hotkey),
      let stored = try? JSONDecoder().decode(HotkeyBinding.self, from: data)
    {
      hotkey = stored
    } else {
      hotkey = .default
    }
  }

  private func persistHotkey() {
    if let data = try? JSONEncoder().encode(hotkey) {
      UserDefaults.standard.set(data, forKey: Keys.hotkey)
    }
  }

  private enum Keys {
    static let hotkey = "meant.hotkey"
  }
}
