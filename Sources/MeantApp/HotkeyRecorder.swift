import AppKit
import Carbon.HIToolbox
import MeantCore
import SwiftUI

struct HotkeyRecorder: View {
  @Binding var binding: HotkeyBinding
  @State private var isRecording = false
  @State private var monitor: Any?

  var body: some View {
    HStack(spacing: 8) {
      Text(isRecording ? "Press a shortcut…" : binding.displayName)
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(isRecording ? Color.accentColor : Color.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(
              isRecording ? Color.accentColor : Color.primary.opacity(0.12),
              lineWidth: 1
            )
        )
        .onTapGesture {
          isRecording = true
        }

      Button(isRecording ? "Cancel" : "Change") {
        isRecording.toggle()
      }
    }
    .onChange(of: isRecording) { _, recording in
      if recording {
        startCapture()
      } else {
        stopCapture()
      }
    }
    .onDisappear {
      isRecording = false
      stopCapture()
    }
  }

  private func startCapture() {
    stopCapture()
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      handleKeyDown(event)
    }
  }

  private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
    let extras = event.modifierFlags.intersection([.control, .option, .shift, .command])
    if event.keyCode == UInt16(kVK_Escape), extras.isEmpty {
      DispatchQueue.main.async { isRecording = false }
      return nil
    }
    guard let recorded = HotkeyBinding(event: event) else {
      return nil
    }
    binding = recorded
    DispatchQueue.main.async { isRecording = false }
    return nil
  }

  private func stopCapture() {
    if let monitor {
      NSEvent.removeMonitor(monitor)
      self.monitor = nil
    }
  }
}

extension HotkeyBinding {
  init?(event: NSEvent) {
    let recorded = HotkeyBinding(
      keyCode: event.keyCode,
      modifiers: .from(event.modifierFlags)
    )
    let hasCarbonModifier =
      recorded.modifiers.contains(.control)
      || recorded.modifiers.contains(.option)
      || recorded.modifiers.contains(.command)
    guard hasCarbonModifier else {
      return nil
    }
    self = recorded
  }
}
