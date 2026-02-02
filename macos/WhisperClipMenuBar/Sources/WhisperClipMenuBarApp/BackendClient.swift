import Foundation

struct TranscriptionResult {
    let text: String
    let latencyMS: Int
    let modelDownloaded: Bool
    let refined: Bool
    let workflowMode: SmartWorkflowMode
}

enum BackendError: LocalizedError {
    case executableNotFound(String)
    case commandFailed(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let path):
            return "Python executable not found: \(path)"
        case .commandFailed(let reason):
            return reason
        case .invalidResponse(let raw):
            return "Invalid backend response: \(raw)"
        }
    }
}

final class BackendClient {
    private let fileManager = FileManager.default

    private var stateDir: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("WhisperClipMac/state", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func recordStart(model: String, language: String) async throws -> [String: Any] {
        let payload = try await runBackend(args: [
            "record", "--start",
            "--state-dir", stateDir.path,
            "--model", model,
            "--language", language,
        ])
        if (payload["status"] as? String) != "ok" {
            throw BackendError.commandFailed(payload["error"] as? String ?? "record start failed")
        }
        return payload
    }

    func recordStop(
        model: String,
        language: String,
        smartRefineEnabled: Bool,
        smartWorkflowMode: SmartWorkflowMode
    ) async throws -> TranscriptionResult {
        let payload = try await runBackend(args: [
            "record", "--stop",
            "--state-dir", stateDir.path,
            "--model", model,
            "--language", language,
            "--smart-mode", smartWorkflowMode.rawValue,
            "--smart-refine-enabled", smartRefineEnabled ? "true" : "false",
        ])
        if (payload["status"] as? String) != "ok" {
            throw BackendError.commandFailed(payload["error"] as? String ?? "record stop failed")
        }
        let text = payload["text"] as? String ?? ""
        let latency = payload["latency_ms"] as? Int ?? 0
        let modelDownloaded = payload["model_downloaded"] as? Bool ?? false
        let refined = payload["refined"] as? Bool ?? false
        let workflowModeRawValue = payload["workflow_mode"] as? String ?? SmartWorkflowMode.normal.rawValue
        let workflowMode = SmartWorkflowMode(rawValue: workflowModeRawValue) ?? .normal
        return TranscriptionResult(
            text: text,
            latencyMS: latency,
            modelDownloaded: modelDownloaded,
            refined: refined,
            workflowMode: workflowMode
        )
    }

    func isModelAvailableLocally(model: String) async throws -> Bool {
        let payload = try await runBackend(args: [
            "model", "--status",
            "--model", model,
        ])
        if (payload["status"] as? String) != "ok" {
            throw BackendError.commandFailed(payload["error"] as? String ?? "model status failed")
        }
        return payload["is_available"] as? Bool ?? false
    }

    func ensureModelAvailable(model: String) async throws -> Bool {
        let payload = try await runBackend(args: [
            "model", "--ensure",
            "--model", model,
        ])
        if (payload["status"] as? String) != "ok" {
            throw BackendError.commandFailed(payload["error"] as? String ?? "model ensure failed")
        }
        return payload["downloaded"] as? Bool ?? false
    }

    private func runBackend(args: [String]) async throws -> [String: Any] {
        let pythonPath = resolvePythonExecutable()
        guard fileManager.fileExists(atPath: pythonPath) else {
            throw BackendError.executableNotFound(pythonPath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["-m", "stt_backend"] + args

        var env = ProcessInfo.processInfo.environment
        env["PYTHONPATH"] = backendPythonPath()
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        var streamedStderr = Data()
        let stderrQueue = DispatchQueue(label: "whisperclip.backend.stderr")
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            stderrQueue.sync {
                streamedStderr.append(chunk)
            }
            FileHandle.standardError.write(chunk)
        }

        try process.run()
        process.waitUntilExit()
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrDataTail = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        stderrQueue.sync {
            streamedStderr.append(stderrDataTail)
        }
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: streamedStderr, encoding: .utf8) ?? ""

        let lines = stdout
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        guard let jsonLine = lines.last, let data = jsonLine.data(using: .utf8) else {
            throw BackendError.invalidResponse(stdout + "\n" + stderr)
        }
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let payload = obj else {
            throw BackendError.invalidResponse(stdout + "\n" + stderr)
        }

        if process.terminationStatus != 0 && (payload["status"] as? String) != "error" {
            throw BackendError.commandFailed(stderr.isEmpty ? stdout : stderr)
        }

        return payload
    }

    private func resolvePythonExecutable() -> String {
        if let override = ProcessInfo.processInfo.environment["WHISPER_CLIP_PYTHON"], !override.isEmpty {
            return override
        }

        let repo = repoRootURL().path
        let localVenv = URL(fileURLWithPath: repo).appendingPathComponent(".venv/bin/python3").path
        if fileManager.fileExists(atPath: localVenv) {
            return localVenv
        }

        return "/usr/bin/python3"
    }

    private func backendPythonPath() -> String {
        let repo = repoRootURL().path
        return URL(fileURLWithPath: repo).appendingPathComponent("backend").path
    }

    private func repoRootURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["WHISPER_CLIP_REPO_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }

        var current = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        for _ in 0..<6 {
            let candidate = current.appendingPathComponent("backend", isDirectory: true)
            if fileManager.fileExists(atPath: candidate.path) {
                return current
            }
            current.deleteLastPathComponent()
        }

        return URL(fileURLWithPath: fileManager.currentDirectoryPath)
    }
}
