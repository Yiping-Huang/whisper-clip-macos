from __future__ import annotations

import time
from pathlib import Path

_MODEL_CACHE: dict[str, object] = {}


def transcribe_file(
    audio_path: Path,
    model_name: str,
    model_dir: Path,
    language: str,
) -> tuple[str, int]:
    import whisper

    cache_key = f"{model_name}:{model_dir}"
    model = _MODEL_CACHE.get(cache_key)
    if model is None:
        model = whisper.load_model(model_name, download_root=str(model_dir))
        _MODEL_CACHE[cache_key] = model

    kwargs: dict[str, object] = {"fp16": False}
    if language != "auto":
        kwargs["language"] = language

    start = time.time()
    result = model.transcribe(str(audio_path), **kwargs)
    latency_ms = int((time.time() - start) * 1000)
    text = (result.get("text") or "").strip()
    return text, latency_ms
