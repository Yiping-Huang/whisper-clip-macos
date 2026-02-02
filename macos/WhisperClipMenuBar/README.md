# WhisperClipMenuBar (macOS)

SwiftUI menu bar app that controls the Python backend (`stt_backend`).

## Features

- Global hotkey: `Option + Command + S` (toggle start/stop)
- Menu bar state icons: idle / recording / transcribing / copied / failed
- Notification on success/failure
- Always copies transcript to clipboard
- Optional auto-paste (`Cmd+V`) after transcription
- Menu actions: show/copy last transcription

## Build & run (dev mode)

From repo root:

```bash
./scripts/setup_macos_backend.sh
./scripts/run_macos_menu_bar.sh
```

or manually:

```bash
source .venv/bin/activate
cd macos/WhisperClipMenuBar
WHISPER_CLIP_REPO_ROOT="$(cd ../.. && pwd)" \
WHISPER_CLIP_PYTHON="$(cd ../.. && pwd)/.venv/bin/python3" \
swift run
```

## Permissions

- **Microphone**: required for backend recording
- **Notifications**: used for success/failure messages
- **Accessibility**: required only when auto-paste is enabled (for simulated `Cmd+V`)

## Notes

- Default backend model is `small`.
- Model files are downloaded to repo `model/`.
- Backend state lives in `~/Library/Application Support/WhisperClipMac/state`.
