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
                Text(appState.llmStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(appState.status == .recording ? "Stop Recording" : "Start Recording") {
                    appState.toggleRecording()
                }

                Divider()

                Toggle("Auto Paste after transcription", isOn: $appState.autoPasteAfterTranscription)
                Toggle("Sound cues", isOn: $appState.soundCuesEnabled)
                Toggle("Transcribing loop sound", isOn: $appState.transcribingLoopSoundEnabled)
                Toggle("Smart refine (LLM)", isOn: $appState.smartRefineEnabled)
                Picker("AI Backend", selection: Binding(
                    get: { appState.llmBackendProvider },
                    set: { appState.llmBackendProvider = $0 }
                )) {
                    ForEach(LLMBackendProvider.allCases, id: \.rawValue) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                if let actionTitle = appState.llmBackendProvider.actionButtonTitle {
                    Button(actionTitle) {
                        appState.runLLMProviderAction()
                    }
                    .disabled(appState.llmBackendProvider == .codexCLI ? !appState.canRunCodexLogin : appState.isLLMActionRunning)
                }
                if appState.llmBackendProvider == .openAIAPI && appState.isOpenAICredentialsEditorVisible {
                    VStack(alignment: .leading, spacing: 8) {
                        SecureField("API Key", text: $appState.openAIApiKeyDraft)
                            .textFieldStyle(.roundedBorder)
                        TextField("Model", text: $appState.openAIModelDraft)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Button("Cancel") {
                                appState.cancelOpenAICredentialsEditing()
                            }
                            Button("Save") {
                                appState.commitOpenAICredentialsEditing()
                            }
                        }
                    }
                }
                Picker("Smart mode", selection: Binding(
                    get: { appState.smartWorkflowMode },
                    set: { appState.smartWorkflowMode = $0 }
                )) {
                    ForEach(SmartWorkflowMode.refinementModes, id: \.rawValue) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .disabled(!appState.smartRefineEnabled)

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
            .onChange(of: appState.soundCuesEnabled) { _ in
                appState.refreshTranscribingLoopSound()
            }
            .onChange(of: appState.transcribingLoopSoundEnabled) { _ in
                appState.refreshTranscribingLoopSound()
            }
            .onChange(of: appState.whisperModel) { newModel in
                appState.warmUpModelIfNeeded(newModel)
            }
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
