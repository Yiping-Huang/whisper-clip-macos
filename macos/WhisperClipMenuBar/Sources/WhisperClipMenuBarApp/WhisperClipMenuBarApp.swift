import AppKit
import SwiftUI

@main
struct WhisperClipMenuBarApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 10) {
                Text("Status: \(appState.statusText)")
                Text(appState.hotKeyDisplayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(appState.notificationStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(appState.status == .recording ? "Stop Recording" : "Start Recording") {
                    appState.toggleRecording()
                }

                Divider()

                Toggle("Auto Paste after transcription", isOn: $appState.autoPasteAfterTranscription)
                Toggle("Sound cues", isOn: $appState.soundCuesEnabled)

                Picker("Model", selection: $appState.whisperModel) {
                    Text("base").tag("base")
                    Text("small").tag("small")
                    Text("medium").tag("medium")
                    Text("large").tag("large")
                }

                Picker("Language", selection: $appState.whisperLanguage) {
                    Text("auto").tag("auto")
                    Text("en").tag("en")
                    Text("zh").tag("zh")
                    Text("ja").tag("ja")
                }

                Divider()

                Button("Show last transcription") {
                    showLastTranscriptionWindow(appState.lastTranscription)
                }
                .disabled(appState.lastTranscription.isEmpty)

                Button("Copy last transcription") {
                    appState.copyLastTranscription()
                }
                .disabled(appState.lastTranscription.isEmpty)

                if !appState.lastError.isEmpty {
                    Text("Error: \(appState.lastError)")
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Divider()
                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
            .padding(12)
            .frame(width: 300)
        } label: {
            Image(systemName: appState.statusIconName)
                .onAppear {
                    appState.start()
                }
        }
        .menuBarExtraStyle(.window)

        Settings {
            EmptyView()
        }
    }

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    private func showLastTranscriptionWindow(_ text: String) {
        guard !text.isEmpty else { return }
        let alert = NSAlert()
        alert.icon = nil
        alert.messageText = "Last Transcription"
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
