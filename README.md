# Whisper Clip (macOS)

Whisper Clip is a local speech-to-text menu bar app for macOS.

- **Frontend**: SwiftUI menu bar app in `macos/WhisperClipMenuBar`
- **Backend**: Python Whisper/audio CLI in `backend/stt_backend`

## Prerequisites (macOS)

- Xcode Command Line Tools (`xcode-select --install`)
- Homebrew
- Python 3.11 (`brew install python@3.11`)
- FFmpeg for Whisper decoding (`brew install ffmpeg`)
- PortAudio for microphone capture (`brew install portaudio`)

## Architecture

- `macos/WhisperClipMenuBar`: menu bar UI, global hotkey, notifications, clipboard/auto-paste
- `backend/stt_backend`: recording + transcription with JSON responses
- `scripts/setup_macos_backend.sh`: create venv and install Python deps
- `scripts/run_macos_menu_bar.sh`: run the Swift app in dev mode

## Smart refine modes

The menu now includes:
- `Smart refine (LLM)` toggle
- `Smart mode` picker with:
  - `Email Dictation` (uses email polishing prompt template)
  - `Work Chat` (uses Slack/Teams-style polishing prompt template)
  - `Technical Ticket` (structures content for Jira/Linear/GitHub Issues)

For these smart modes, the backend can call your selected AI backend after transcription.

## AI backend options

The `AI Backend` picker supports:
- `Pure Chat Mode (Codex CLI)`
- `OpenAI API (ChatGPT)`
- `Azure OpenAI (Placeholder)`

Codex setup:
- Install Codex CLI manually: `brew install codex`
- Then click `Codex Login` in the app to authenticate
- If Codex is not installed, the `Codex Login` button is intentionally disabled

Implement your API integration in:

- `backend/stt_backend/user_llm_bridge.py`
- Optional glossary context for repeated names/terms is in:
  - `backend/stt_backend/user_glossary.py`

Required hook contract:

```python
def query_llm(user_query: str) -> str:
    ...
```

Prompt templates are in:

- `backend/stt_backend/prompt_templates.py`

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

1) Install system dependencies (once):

```bash
# Install Homebrew first if you don't have it: https://brew.sh
brew install python@3.11 ffmpeg portaudio
```

2) Setup backend environment:

```bash
./scripts/setup_macos_backend.sh
```

3) Run menu bar app:

```bash
./scripts/run_macos_menu_bar.sh
```

Default hotkey: **Option + Z**.

If you use Conda, make sure the app still points to repo venv Python:

```bash
echo $WHISPER_CLIP_PYTHON
# expected: <repo>/.venv/bin/python3
```

## First-time model download

- On app launch, the currently selected model is checked and pre-downloaded if needed.
- If you switch to a model you have never used, the app also pre-downloads it in the background.
- During this step, status shows **Downloading model…**.
- The transcribing loop sound is only used during actual **Transcribing…** (not during model download).
- Download time depends on model size and network speed (for `small`, usually tens of seconds on first run).

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
- Whisper models are stored in `model/` and downloaded when first selected.
