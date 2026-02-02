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

    @AppStorage("autoPasteAfterTranscription") var autoPasteAfterTranscription: Bool = false
    @AppStorage("whisperModel") var whisperModel: String = "small"
    @AppStorage("whisperLanguage") var whisperLanguage: String = "auto"
    @AppStorage("soundCuesEnabled") var soundCuesEnabled: Bool = true

    private let backend = BackendClient()
    private var hotKeyManager: GlobalHotKeyManager?

    func start() {
        hotKeyManager = GlobalHotKeyManager(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(cmdKey | optionKey)) { [weak self] in
            Task { @MainActor in
                self?.toggleRecording()
            }
        }
        hotKeyManager?.register()
        NotificationClient.shared.requestAuthorization()
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

    private func startRecording() {
        status = .recording
        statusText = "Recording…"
        lastError = ""
        playCueIfNeeded()
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
        status = .transcribing
        statusText = "Transcribing…"
        playCueIfNeeded()
        let model = whisperModel
        let language = whisperLanguage
        let autoPaste = autoPasteAfterTranscription

        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.backend.recordStop(model: model, language: language)
                await MainActor.run {
                    self.lastTranscription = result.text
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.text, forType: .string)
                    if autoPaste {
                        _ = AutoPaste.pasteClipboardUsingCmdV()
                    }
                    self.status = .copied
                    self.statusText = "Copied ✅"
                    NotificationClient.shared.send(title: "Whisper Clip", body: "Transcription copied to clipboard")
                    self.playCueIfNeeded()
                }
            } catch {
                await MainActor.run {
                    self.applyFailure(error.localizedDescription)
                }
            }
        }
    }

    private func applyFailure(_ message: String) {
        lastError = message
        status = .failed
        statusText = "Failed ❌"
        NotificationClient.shared.send(title: "Whisper Clip Failed", body: message)
    }

    private func playCueIfNeeded() {
        guard soundCuesEnabled else { return }
        NSSound.beep()
    }
}
