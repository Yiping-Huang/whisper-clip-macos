# Backend (stt_backend)

The backend is a Python CLI package used by the macOS menu bar app.

## Entry point

Run from repo root:

```bash
PYTHONPATH=backend python -m stt_backend --help
```

## Commands

Start recording:

```bash
PYTHONPATH=backend python -m stt_backend record --start --model small --language auto
```

Stop recording + transcribe:

```bash
PYTHONPATH=backend python -m stt_backend record --stop --model small --language auto
```

Toggle recording (single command mode):

```bash
PYTHONPATH=backend python -m stt_backend run --mode toggle --model small --language auto
```

## JSON output contract

Success:

```json
{ "status": "ok", "text": "...", "latency_ms": 1234 }
```

Failure:

```json
{ "status": "error", "error": "..." }
```

## Logging

Backend logs are written to `backend/logs/stt_backend.log`.
