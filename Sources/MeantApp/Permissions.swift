import AppKit
import ApplicationServices
import CoreGraphics

enum Permissions {
  static var accessibility: Bool {
    AXIsProcessTrusted()
  }

  static var inputMonitoring: Bool {
    CGPreflightListenEventAccess()
  }

  static var allGranted: Bool {
    accessibility && inputMonitoring
  }

  @discardableResult
  static func requestAccessibility() -> Bool {
    AXIsProcessTrustedWithOptions(
      ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    )
  }

  @discardableResult
  static func requestInputMonitoring() -> Bool {
    CGRequestListenEventAccess()
  }

  static func openAccessibilitySettings() {
    openPrivacyPane("Privacy_Accessibility")
  }

  static func openInputMonitoringSettings() {
    openPrivacyPane("Privacy_ListenEvent")
  }

  private static func openPrivacyPane(_ pane: String) {
    let urls = [
      "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(pane)",
      "x-apple.systempreferences:com.apple.preference.security?\(pane)",
    ]
    for string in urls {
      guard let url = URL(string: string) else {
        continue
      }
      if NSWorkspace.shared.open(url) {
        return
      }
    }
  }
}
