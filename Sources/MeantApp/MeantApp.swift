import AppKit
import Carbon.HIToolbox
import MeantCore
import SwiftUI

@main
struct MeantApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @ObservedObject private var settings = SettingsStore.shared

  var body: some Scene {
    MenuBarExtra {
      Button("Flip last word") {
        AppDelegate.shared?.model.handleHotkey()
      }
      .applyHotkey(settings.hotkey)
      Divider()
      Button("Settings…") {
        AppChrome.showSettings()
      }
      .keyboardShortcut(",", modifiers: .command)
      Divider()
      Button("Quit") {
        NSApp.terminate(nil)
      }
    } label: {
      MenuBarLabel()
    }
    .menuBarExtraStyle(.menu)

    Window("Settings", id: "settings") {
      SettingsView()
        .background(SettingsWindowChrome())
    }
    .windowResizability(.contentSize)
  }
}

private struct MenuBarLabel: View {
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Label("meant", systemImage: "arrow.left.arrow.right")
      .onAppear {
        AppChrome.openSettingsWindow = {
          openWindow(id: "settings")
        }
      }
  }
}

private struct SettingsWindowChrome: View {
  var body: some View {
    Color.clear
      .onAppear {
        AppChrome.becomeRegularApp()
      }
      .onDisappear {
        DispatchQueue.main.async {
          AppChrome.resignToMenuBarIfNeeded()
        }
      }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  static var shared: AppDelegate?
  let model = AppModel()

  func applicationDidFinishLaunching(_ notification: Notification) {
    Self.shared = self
    NSApp.setActivationPolicy(.accessory)
    model.start()
    if !Permissions.allGranted {
      AppChrome.showSettings()
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    AppChrome.resignToMenuBarIfNeeded()
    return false
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      AppChrome.showSettings()
    } else {
      AppChrome.becomeRegularApp()
    }
    return true
  }
}

private extension View {
  @ViewBuilder
  func applyHotkey(_ hotkey: HotkeyBinding) -> some View {
    if let key = hotkey.keyEquivalent {
      keyboardShortcut(key, modifiers: hotkey.eventModifiers)
    } else {
      self
    }
  }
}

private extension HotkeyBinding {
  var eventModifiers: SwiftUI.EventModifiers {
    var result: SwiftUI.EventModifiers = []
    if modifiers.contains(.control) { result.insert(.control) }
    if modifiers.contains(.option) { result.insert(.option) }
    if modifiers.contains(.shift) { result.insert(.shift) }
    if modifiers.contains(.command) { result.insert(.command) }
    return result
  }

  var keyEquivalent: KeyEquivalent? {
    if let character = layoutCharacter?.lowercased().first {
      return KeyEquivalent(character)
    }
    switch Int(keyCode) {
    case kVK_Space: return " "
    case kVK_Return, kVK_ANSI_KeypadEnter: return .return
    case kVK_Tab: return .tab
    case kVK_Escape: return .escape
    default:
      return nil
    }
  }
}
