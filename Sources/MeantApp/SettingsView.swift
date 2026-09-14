import AppKit
import MeantCore
import SwiftUI

struct SettingsView: View {
  @ObservedObject private var settings = SettingsStore.shared
  @ObservedObject private var ignored = IgnoreStore.shared
  @State private var accessibility = Permissions.accessibility
  @State private var inputMonitoring = Permissions.inputMonitoring
  @State private var selectedIgnore = Set<String>()
  @State private var newIgnore = ""
  @State private var tab: SettingsTab = .general

  var body: some View {
    TabView(selection: $tab) {
      generalTab
        .tabItem { Label("General", systemImage: "gearshape") }
        .tag(SettingsTab.general)
      ignoreTab
        .tabItem { Label("Ignore", systemImage: "nosign") }
        .tag(SettingsTab.ignore)
    }
    .frame(width: 500, height: 540)
    .onAppear(perform: refresh)
    .onChange(of: settings.hotkey) { _, hotkey in
      HotKeyMonitor.shared.register(hotkey)
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      refresh()
    }
    .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
      refresh()
    }
  }

  private var generalTab: some View {
    Form {
      Section {
        VStack(alignment: .leading, spacing: 4) {
          Text("meant")
            .font(.title2.weight(.semibold))
          Text("Wrong-layout words become what you meant.")
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
      }

      Section {
        HotkeyRecorder(binding: $settings.hotkey)
      } header: {
        Text("Hotkey")
      } footer: {
        Text("Include ⌃, ⌥, or ⌘.")
      }

      Section {
        Text("Ask before flipping a wrong-layout word.")
          .frame(maxWidth: .infinity, alignment: .leading)
      } header: {
        Text("Space")
      }

      Section {
        permissionButton(
          granted: accessibility,
          onLabel: "Accessibility is on",
          offLabel: "Allow Accessibility…"
        ) {
          _ = Permissions.requestAccessibility()
          Permissions.openAccessibilitySettings()
        }
        permissionButton(
          granted: inputMonitoring,
          onLabel: "Input Monitoring is on",
          offLabel: "Allow Input Monitoring…"
        ) {
          _ = Permissions.requestInputMonitoring()
          Permissions.openInputMonitoringSettings()
        }
      } header: {
        Text("Permissions")
      } footer: {
        Text("Accessibility replaces the word. Input Monitoring watches Space.")
      }
    }
    .formStyle(.grouped)
    .scrollBounceBehavior(.basedOnSize)
    .padding(8)
  }

  private var ignoreTab: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("These words never show a HUD. Tab on a suggestion adds them.")
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)

      Table(ignoreRows, selection: $selectedIgnore) {
        TableColumn("Word") { row in
          Text(row.word)
            .font(.body.monospaced())
        }
      }
      .tableStyle(.inset(alternatesRowBackgrounds: !ignored.words.isEmpty))
      .overlay {
        if ignored.words.isEmpty {
          Text("None yet")
            .foregroundStyle(.secondary)
        }
      }
      .onDeleteCommand(perform: removeSelected)

      HStack(spacing: 8) {
        Button {
          removeSelected()
        } label: {
          Image(systemName: "minus")
            .frame(width: 14, height: 14)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle)
        .controlSize(.regular)
        .frame(width: 28, height: 28)
        .disabled(selectedIgnore.isEmpty)
        .help("Remove selected")

        TextField("Add a word", text: $newIgnore)
          .textFieldStyle(.roundedBorder)
          .controlSize(.small)
          .onSubmit(addIgnore)
        Button("Add", action: addIgnore)
          .controlSize(.small)
          .disabled(newIgnore.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
    }
  }

  private var ignoreRows: [IgnoreRow] {
    ignored.words.map(IgnoreRow.init)
  }

  private func addIgnore() {
    let token = newIgnore.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty else {
      return
    }
    ignored.add([token])
    AppDelegate.shared?.model.reloadDetector()
    newIgnore = ""
  }

  private func removeSelected() {
    for id in selectedIgnore {
      ignored.remove(id)
    }
    selectedIgnore.removeAll()
    AppDelegate.shared?.model.reloadDetector()
  }

  private func permissionButton(
    granted: Bool,
    onLabel: String,
    offLabel: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(granted ? onLabel : offLabel, action: action)
      .disabled(granted)
  }

  private func refresh() {
    let wasInputMonitoring = inputMonitoring
    accessibility = Permissions.accessibility
    inputMonitoring = Permissions.inputMonitoring
    if inputMonitoring, !wasInputMonitoring {
      AppDelegate.shared?.model.restartInputTap()
    }
  }
}

private enum SettingsTab: Hashable {
  case general
  case ignore
}

private struct IgnoreRow: Identifiable, Hashable {
  let word: String
  var id: String { word }
}
