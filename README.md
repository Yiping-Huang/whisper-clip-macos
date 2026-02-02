# Whisper Clip (macOS)

Whisper Clip is a local speech-to-text menu bar app for macOS.

- **Frontend**: SwiftUI menu bar app in `macos/WhisperClipMenuBar`
- **Backend**: Python Whisper/audio CLI in `backend/stt_backend`

## Architecture

- `macos/WhisperClipMenuBar`: menu bar UI, global hotkey, notifications, clipboard/auto-paste
- `backend/stt_backend`: recording + transcription with JSON responses
- `scripts/setup_macos_backend.sh`: create venv and install Python deps
- `scripts/run_macos_menu_bar.sh`: run the Swift app in dev mode

## STT/audio stack

- Whisper inference: `openai-whisper`
- Default model: `small` (configurable in app menu)
- Audio capture: `sounddevice.InputStream`

## Backend CLI contract

```bash
PYTHONPATH=backend python -m stt_backend record --start --model small --language auto
PYTHONPATH=backend python -m stt_backend record --stop --model small --language auto
```

Success JSON:

```json
{ "status": "ok", "text": "...", "latency_ms": 1234 }
```

Error JSON:

```json
{ "status": "error", "error": "..." }
```

## Build & run (dev mode)

1) Setup backend environment:

```bash
./scripts/setup_macos_backend.sh
```

2) Run menu bar app:

```bash
./scripts/run_macos_menu_bar.sh
```

Default hotkey: **Option + Command + S**.

## Permissions (macOS)

- Microphone (required)
- Notifications (recommended)
- Accessibility (required only for auto-paste)

## Logs and state

- Backend log: `backend/logs/stt_backend.log`
- Recorder state/temp audio: `~/Library/Application Support/WhisperClipMac/state`

## Distribution notes

- Current mode is source/dev workflow (Swift app calls Python in venv)
- Optional production paths:
  1. Bundle a frozen backend binary (PyInstaller)
  2. Embed Python runtime + backend into app resources

## Assumptions

- This repo is now focused on macOS only.
- Whisper models download to `model/` on first use.
