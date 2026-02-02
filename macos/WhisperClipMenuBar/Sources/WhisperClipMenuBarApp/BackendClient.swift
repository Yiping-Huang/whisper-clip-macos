import Foundation

struct TranscriptionResult {
    let text: String
    let latencyMS: Int
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

    func recordStop(model: String, language: String) async throws -> TranscriptionResult {
        let payload = try await runBackend(args: [
            "record", "--stop",
            "--state-dir", stateDir.path,
            "--model", model,
            "--language", language,
        ])
        if (payload["status"] as? String) != "ok" {
            throw BackendError.commandFailed(payload["error"] as? String ?? "record stop failed")
        }
        let text = payload["text"] as? String ?? ""
        let latency = payload["latency_ms"] as? Int ?? 0
        return TranscriptionResult(text: text, latencyMS: latency)
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
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

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
