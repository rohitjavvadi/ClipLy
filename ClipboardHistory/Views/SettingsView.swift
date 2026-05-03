import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var appState: AppState
    @State private var isRecordingShortcut = false
    @State private var shortcutMonitor: Any?
    @State private var isShowingDeleteAllDataConfirmation = false

    var body: some View {
        Form {
            Picker("Keep history", selection: $appState.settings.retentionPeriod) {
                ForEach(RetentionPeriod.allCases) { period in
                    Text(period.title).tag(period)
                }
            }
            Toggle("Pause clipboard capture", isOn: $appState.settings.capturePaused)
            Toggle("Launch at login", isOn: launchAtLoginBinding)
            Toggle("Show Dock icon", isOn: showDockIconBinding)
            LabeledContent("Open shortcut") {
                Button(isRecordingShortcut ? "Press keys…" : appState.settings.shortcutDisplayName) {
                    toggleShortcutRecording()
                }
                .buttonStyle(.bordered)
            }
            if let launchAtLoginError = appState.launchAtLoginError {
                Text(launchAtLoginError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Button("Clear History", role: .destructive) {
                appState.clearHistory()
            }
            Button("Delete All ClipLy Data…", role: .destructive) {
                isShowingDeleteAllDataConfirmation = true
            }
        }
        .padding(24)
        .frame(width: 420)
        .alert("Delete all ClipLy data?", isPresented: $isShowingDeleteAllDataConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete and Quit", role: .destructive) {
                appState.deleteAllDataAndQuit()
            }
        } message: {
            Text("This removes clipboard history, stored images, thumbnails, settings, and launch-at-login registration. ClipLy will quit after cleanup.")
        }
        .onAppear {
            appState.refreshLaunchAtLoginState()
        }
        .onDisappear {
            stopShortcutRecording()
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { appState.launchAtLoginEnabled },
            set: { appState.setLaunchAtLogin($0) }
        )
    }

    private var showDockIconBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.showDockIcon },
            set: { appState.setShowDockIcon($0) }
        )
    }

    private func toggleShortcutRecording() {
        isRecordingShortcut ? stopShortcutRecording() : startShortcutRecording()
    }

    private func startShortcutRecording() {
        stopShortcutRecording()
        isRecordingShortcut = true
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = ShortcutFormatter.carbonModifiers(from: event.modifierFlags)
            let keyCode = UInt32(event.keyCode)
            if ShortcutFormatter.isUsableShortcut(keyCode: keyCode, modifiers: modifiers) {
                appState.updateShortcut(keyCode: keyCode, modifiers: modifiers)
            }
            stopShortcutRecording()
            return nil
        }
    }

    private func stopShortcutRecording() {
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
            self.shortcutMonitor = nil
        }
        isRecordingShortcut = false
    }
}
