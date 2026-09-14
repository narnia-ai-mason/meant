import SwiftUI

struct HUDView: View {
  var original: String
  var replacement: String
  var onConfirm: () -> Void
  var onIgnore: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      Text(original)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Text("→")
        .foregroundStyle(.tertiary)
      Text(replacement)
        .fontWeight(.medium)
        .lineLimit(1)
      Button("Change ↩") {
        onConfirm()
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.small)
      Button("Ignore ⇥") {
        onIgnore()
      }
      .buttonStyle(.plain)
      .controlSize(.small)
      .foregroundStyle(.secondary)
    }
    .font(.system(size: 13))
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(.ultraThinMaterial, in: Capsule())
    .overlay(
      Capsule()
        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
    )
    .fixedSize()
  }
}
