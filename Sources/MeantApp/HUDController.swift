import AppKit
import MeantCore
import SwiftUI

@MainActor
final class HUDController: NSObject {
  enum Key {
    case escape
    case commit
    case ignore
  }

  var isVisible: Bool { panel != nil }
  var onCancel: (() -> Void)?
  var onVisibilityChange: ((Bool) -> Void)?

  private var panel: NSPanel?
  private var globalMonitor: Any?
  private var onConfirm: (() -> Void)?
  private var onIgnore: (() -> Void)?
  private var confirming = false

  func show(
    original: String,
    replacement: String,
    anchor: CGRect?,
    onConfirm: @escaping () -> Void,
    onIgnore: @escaping () -> Void
  ) {
    self.onConfirm = onConfirm
    self.onIgnore = onIgnore
    confirming = false
    present(
      HUDView(
        original: original,
        replacement: replacement,
        onConfirm: { [weak self] in
          self?.confirm()
        },
        onIgnore: { [weak self] in
          self?.ignore()
        }
      ),
      anchor: anchor
    )
  }

  func hide() {
    hide(reason: .cancel)
  }

  func handle(_ key: Key) {
    switch key {
    case .escape:
      hide(reason: .cancel)
    case .commit:
      confirm()
    case .ignore:
      ignore()
    }
  }

  private enum DismissReason {
    case cancel
    case commit
  }

  private func hide(reason: DismissReason) {
    if let globalMonitor {
      NSEvent.removeMonitor(globalMonitor)
      self.globalMonitor = nil
    }
    panel?.orderOut(nil)
    panel = nil
    onConfirm = nil
    onIgnore = nil
    onVisibilityChange?(false)
    if reason == .cancel {
      confirming = false
      onCancel?()
    }
  }

  private func ignore() {
    let ignore = onIgnore
    hide(reason: .cancel)
    ignore?()
  }

  private func confirm() {
    guard !confirming else {
      return
    }
    confirming = true
    let commit = onConfirm
    hide(reason: .commit)
    commit?()
  }

  private func present(_ view: HUDView, anchor: CGRect?) {
    let host = NSHostingView(rootView: view)
    host.sizingOptions = [.intrinsicContentSize]
    host.frame.size = host.fittingSize

    let panel = self.panel ?? makePanel()
    panel.contentView = host
    panel.setContentSize(host.fittingSize)
    panel.setFrameOrigin(origin(for: panel.frame.size, anchor: anchor))
    panel.orderFrontRegardless()
    self.panel = panel
    onVisibilityChange?(true)
    installMonitorIfNeeded()
  }

  private func makePanel() -> NSPanel {
    let panel = KeyPanel(
      contentRect: .zero,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.level = .statusBar
    panel.collectionBehavior = [
      .canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle,
    ]
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = true
    return panel
  }

  private func origin(for size: CGSize, anchor: CGRect?) -> NSPoint {
    let point = anchor?.origin
    let screen = point.flatMap { candidate in
      NSScreen.screens.first { NSMouseInRect(candidate, $0.frame, false) }
    } ?? NSScreen.main ?? NSScreen.screens.first
    let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
    let origin = HUDPlacement.origin(size: size, anchor: anchor, visible: visible)
    return NSPoint(x: origin.x, y: origin.y)
  }

  private func installMonitorIfNeeded() {
    guard globalMonitor == nil else {
      return
    }
    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
      guard let self, let panel = self.panel else {
        return
      }
      if !panel.frame.contains(NSEvent.mouseLocation) {
        DispatchQueue.main.async { self.hide() }
      }
    }
  }
}

private final class KeyPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}
