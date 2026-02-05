import AppKit
import Carbon
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum Status: String {
        case idle
        case recording
        case transcribing
        case copied
        case failed
    }

    @Published var status: Status = .idle
    @Published var statusText: String = "Idle"
    @Published var lastTranscription: String = ""
    @Published var lastError: String = ""
    @Published var llmStatusText: String = "LLM backend: not checked"
    @Published var isLLMActionRunning: Bool = false
    @Published var isOpenAICredentialsEditorVisible: Bool = false
    @Published var openAIApiKeyDraft: String = ""
    @Published var openAIModelDraft: String = "gpt-4o-mini"
    @Published var isCodexInstalled: Bool = false
    @Published var isCodexAuthenticated: Bool = false

    @AppStorage("autoPasteAfterTranscription") var autoPasteAfterTranscription: Bool = false
    @AppStorage("whisperModel") var whisperModel: String = "small"
    @AppStorage("whisperLanguage") var whisperLanguage: String = "auto"
    @AppStorage("soundCuesEnabled") var soundCuesEnabled: Bool = true
    @AppStorage("transcribingLoopSoundEnabled") var transcribingLoopSoundEnabled: Bool = true
    @AppStorage("smartRefineEnabled") var smartRefineEnabled: Bool = false
    @AppStorage("smartWorkflowMode") private var smartWorkflowModeRawValue: String = SmartWorkflowMode.email.rawValue
    @AppStorage("llmBackendProvider") private var llmBackendProviderRawValue: String = LLMBackendProvider.codexCLI.rawValue
    @AppStorage("openAIApiKey") var openAIApiKey: String = ""
    @AppStorage("openAIModel") var openAIModel: String = "gpt-4o-mini"

    // Carbon global hotkeys do not support Fn as a modifier, so we use Option+Z.
    private let hotKeyCode: UInt32 = UInt32(kVK_ANSI_Z)
    private let hotKeyModifiers: UInt32 = UInt32(optionKey)

    private let backend = BackendClient()
    private var hotKeyManager: GlobalHotKeyManager?
    private var didStart = false
    private var transcribingLoopSound: NSSound?
    private var modelWarmupTask: Task<Void, Never>?

    func start() {
        guard !didStart else { return }
        didStart = true

        hotKeyManager = GlobalHotKeyManager(keyCode: hotKeyCode, modifiers: hotKeyModifiers) { [weak self] in
            Task { @MainActor in
                self?.toggleRecording()
            }
        }
        hotKeyManager?.register()
        NotificationClient.shared.requestAuthorization()
        warmUpModelIfNeeded(whisperModel)
        normalizeSmartWorkflowModeIfNeeded()
        refreshLLMStatus()
    }

    var statusIconName: String {
        switch status {
        case .idle: return "mic"
        case .recording: return "waveform.circle.fill"
        case .transcribing: return "hourglass.circle.fill"
        case .copied: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var notificationStatusText: String {
        if NotificationClient.shared.notificationsAvailable {
            return "Notifications: enabled"
        }
        return "Notifications: skipped in dev mode"
    }

    var hotKeyDisplayText: String {
        "Hotkey: Option + Z"
    }

    var smartWorkflowMode: SmartWorkflowMode {
        get { SmartWorkflowMode(rawValue: smartWorkflowModeRawValue) ?? .normal }
        set { smartWorkflowModeRawValue = newValue.rawValue }
    }

    var canRunCodexLogin: Bool {
        llmBackendProvider == .codexCLI && isCodexInstalled && !isLLMActionRunning
    }

    var llmBackendProvider: LLMBackendProvider {
        get { LLMBackendProvider(rawValue: llmBackendProviderRawValue) ?? .codexCLI }
        set {
            llmBackendProviderRawValue = newValue.rawValue
            refreshLLMStatus()
        }
    }

    func toggleRecording() {
        switch status {
        case .idle, .copied, .failed:
            startRecording()
        case .recording:
            stopRecordingAndTranscribe()
        case .transcribing:
            break
        }
    }

    func copyLastTranscription() {
        guard !lastTranscription.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastTranscription, forType: .string)
        status = .copied
        statusText = "Copied ✅"
    }

    func refreshTranscribingLoopSound() {
        guard status == .transcribing else {
            stopTranscribingLoopIfNeeded()
            return
        }

        if soundCuesEnabled && transcribingLoopSoundEnabled {
            startTranscribingLoopIfNeeded()
        } else {
            stopTranscribingLoopIfNeeded()
        }
    }

    func warmUpModelIfNeeded(_ model: String) {
        modelWarmupTask?.cancel()
        modelWarmupTask = Task.detached { [weak self] in
            guard let self else { return }
            do {
                let isAvailable = try await self.backend.isModelAvailableLocally(model: model)
                if isAvailable {
                    return
                }
                await MainActor.run {
                    if self.status == .idle {
                        self.statusText = "Downloading model…"
                    }
                    self.log("Downloading model '\(model)'...")
                }
                _ = try await self.backend.ensureModelAvailable(model: model)
                await MainActor.run {
                    if self.status == .idle {
                        self.statusText = "Idle"
                    }
                    self.log("Model '\(model)' is ready.")
                }
            } catch {
                // Keep warm-up best effort; transcription path will retry and surface real errors.
            }
        }
    }

    private func startRecording() {
        status = .recording
        statusText = "Recording…"
        lastError = ""
        playCueIfNeeded(.recordingStart)
        let model = whisperModel
        let language = whisperLanguage

        Task.detached { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.backend.recordStart(model: model, language: language)
            } catch {
                await MainActor.run {
                    self.applyFailure(error.localizedDescription)
                }
            }
        }
    }

    private func stopRecordingAndTranscribe() {
        let autoPaste = autoPasteAfterTranscription
        let smartRefineEnabled = self.smartRefineEnabled
        let smartMode = self.smartWorkflowMode
        let usesGenerativeRefine = smartRefineEnabled && smartMode != .normal

        status = .transcribing
        statusText = usesGenerativeRefine ? "Transcribing + refining…" : "Transcribing…"
        startTranscribingLoopIfNeeded()
        playCueIfNeeded(.recordingStop)
        let model = whisperModel
        let language = whisperLanguage
        let llmProvider = self.llmBackendProvider
        let openAIApiKey = self.openAIApiKey
        let openAIModel = self.openAIModel

        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let modelIsReady: Bool
                do {
                    modelIsReady = try await self.backend.isModelAvailableLocally(model: model)
                } catch {
                    modelIsReady = true
                }
                if !modelIsReady {
                    await MainActor.run {
                        self.statusText = "Downloading model…"
                        self.log("Downloading model '\(model)'...")
                    }
                    _ = try await self.backend.ensureModelAvailable(model: model)
                    await MainActor.run {
                        self.log("Model '\(model)' is ready.")
                    }
                }

                await MainActor.run {
                    self.statusText = usesGenerativeRefine ? "Transcribing + refining…" : "Transcribing…"
                    self.log(usesGenerativeRefine ? "Transcribing and refining..." : "Transcribing...")
                }

                let result = try await self.backend.recordStop(
                    model: model,
                    language: language,
                    smartRefineEnabled: smartRefineEnabled,
                    smartWorkflowMode: smartMode,
                    llmProvider: llmProvider,
                    openAIApiKey: openAIApiKey,
                    openAIModel: openAIModel
                )
                await MainActor.run {
                    self.stopTranscribingLoopIfNeeded()
                    self.lastTranscription = result.text
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.text, forType: .string)
                    if autoPaste {
                        _ = AutoPaste.pasteClipboardUsingCmdV()
                    }
                    self.status = .copied
                    self.statusText = "Copied ✅"
                    NotificationClient.shared.send(title: "Whisper Clip", body: "Transcription copied to clipboard")
                    self.playCueIfNeeded(.transcriptionComplete)
                }
            } catch {
                await MainActor.run {
                    self.stopTranscribingLoopIfNeeded()
                    self.applyFailure(error.localizedDescription)
                }
            }
        }
    }

    private func applyFailure(_ message: String) {
        stopTranscribingLoopIfNeeded()
        lastError = message
        status = .failed
        statusText = "Failed ❌"
        NotificationClient.shared.send(title: "Whisper Clip Failed", body: message)
    }

    private enum CueKind {
        case recordingStart
        case recordingStop
        case transcriptionComplete
    }

    private func playCueIfNeeded(_ kind: CueKind) {
        guard soundCuesEnabled else { return }
        switch kind {
        case .recordingStart:
            NSSound(named: "Blow")?.play()
        case .recordingStop:
            NSSound(named: "Ping")?.play()
        case .transcriptionComplete:
            NSSound(named: "Pop")?.play()
        }
    }

    private func startTranscribingLoopIfNeeded() {
        guard soundCuesEnabled && transcribingLoopSoundEnabled else { return }
        stopTranscribingLoopIfNeeded()
        guard let sound = NSSound(named: "Purr") else { return }
        sound.volume = 0.12
        sound.loops = true
        sound.play()
        transcribingLoopSound = sound
    }

    private func stopTranscribingLoopIfNeeded() {
        transcribingLoopSound?.stop()
        transcribingLoopSound = nil
    }

    private func log(_ message: String) {
        print("[WhisperClip] \(message)")
    }

    func runLLMProviderAction() {
        switch llmBackendProvider {
        case .codexCLI:
            runCodexLogin()
        case .openAIAPI:
            startOpenAICredentialsEditing()
        case .azureOpenAI:
            break
        }
    }

    func startOpenAICredentialsEditing() {
        openAIApiKeyDraft = openAIApiKey
        openAIModelDraft = openAIModel
        isOpenAICredentialsEditorVisible = true
    }

    func cancelOpenAICredentialsEditing() {
        isOpenAICredentialsEditorVisible = false
    }

    func commitOpenAICredentialsEditing() {
        saveOpenAICredentials(apiKey: openAIApiKeyDraft, model: openAIModelDraft)
        isOpenAICredentialsEditorVisible = false
    }

    func saveOpenAICredentials(apiKey: String, model: String) {
        openAIApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        openAIModel = trimmedModel.isEmpty ? "gpt-4o-mini" : trimmedModel
        refreshLLMStatus()
    }

    func refreshLLMStatus() {
        switch llmBackendProvider {
        case .codexCLI:
            llmStatusText = "LLM backend: checking Codex CLI..."
            Task.detached { [weak self] in
                guard let self else { return }
                do {
                    let status = try await self.backend.codexStatus()
                    await MainActor.run {
                        self.isCodexInstalled = status.installed
                        self.isCodexAuthenticated = status.authenticated
                        self.llmStatusText = "LLM backend: \(status.message)"
                    }
                } catch {
                    await MainActor.run {
                        self.isCodexInstalled = false
                        self.isCodexAuthenticated = false
                        self.llmStatusText = "LLM backend: Codex check failed (\(error.localizedDescription))"
                    }
                }
            }
        case .openAIAPI:
            isCodexInstalled = false
            isCodexAuthenticated = false
            if openAIApiKey.isEmpty {
                llmStatusText = "LLM backend: OpenAI API selected (credentials missing)"
            } else {
                llmStatusText = "LLM backend: OpenAI API active (model: \(openAIModel))"
            }
        case .azureOpenAI:
            isCodexInstalled = false
            isCodexAuthenticated = false
            llmStatusText = "LLM backend: Azure OpenAI selected (placeholder; edit user_llm_bridge.py)"
        }
    }

    private func runCodexLogin() {
        guard isCodexInstalled else {
            llmStatusText = "LLM backend: Codex CLI is not installed. Install with 'brew install codex' first."
            return
        }
        guard !isLLMActionRunning else { return }
        isLLMActionRunning = true
        llmStatusText = "LLM backend: preparing Codex CLI..."

        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let status = try await self.backend.codexLogin()
                await MainActor.run {
                    self.isLLMActionRunning = false
                    self.isCodexInstalled = status.installed
                    self.isCodexAuthenticated = status.authenticated
                    self.llmStatusText = "LLM backend: \(status.message)"
                }
            } catch {
                await MainActor.run {
                    self.isLLMActionRunning = false
                    self.llmStatusText = "LLM backend: Codex login failed (\(error.localizedDescription))"
                }
            }
        }
    }

    private func normalizeSmartWorkflowModeIfNeeded() {
        if smartWorkflowMode == .normal {
            smartWorkflowMode = .email
        }
    }
}
