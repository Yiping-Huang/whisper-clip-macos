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

Stop recording + transcribe + smart refine:

```bash
PYTHONPATH=backend python -m stt_backend record --stop --model small --language auto --smart-mode email --smart-refine-enabled true
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

## Smart refine hook

Implement your own LLM call in:

- `backend/stt_backend/user_llm_bridge.py`

Function signature:

```python
def query_llm(user_query: str) -> str:
    ...
```

Built-in prompt templates for `email`, `work_chat`, and `technical_ticket` are in:

- `backend/stt_backend/prompt_templates.py`

## Logging

Backend logs are written to `backend/logs/stt_backend.log`.
