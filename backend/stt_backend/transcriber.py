from __future__ import annotations

import time
from pathlib import Path

_MODEL_CACHE: dict[str, object] = {}


def model_is_available_locally(model_name: str, model_dir: Path) -> bool:
    import os
    import whisper

    if model_name in whisper._MODELS:  # type: ignore[attr-defined]
        url = whisper._MODELS[model_name]  # type: ignore[attr-defined]
        checkpoint_name = os.path.basename(url)
        return (model_dir / checkpoint_name).is_file()

    # If user passes a local checkpoint file path, treat it as available when present.
    candidate = Path(model_name).expanduser()
    return candidate.is_file()


def ensure_model_available(model_name: str, model_dir: Path) -> bool:
    import whisper

    was_available_before = model_is_available_locally(model_name=model_name, model_dir=model_dir)
    cache_key = f"{model_name}:{model_dir}"
    model = _MODEL_CACHE.get(cache_key)
    if model is None:
        model = whisper.load_model(model_name, download_root=str(model_dir))
        _MODEL_CACHE[cache_key] = model
    return (not was_available_before) and model_is_available_locally(model_name=model_name, model_dir=model_dir)


def transcribe_file(
    audio_path: Path,
    model_name: str,
    model_dir: Path,
    language: str,
) -> tuple[str, int, bool]:
    model_downloaded = ensure_model_available(model_name=model_name, model_dir=model_dir)
    cache_key = f"{model_name}:{model_dir}"
    model = _MODEL_CACHE[cache_key]

    kwargs: dict[str, object] = {"fp16": False}
    if language != "auto":
        kwargs["language"] = language

    start = time.time()
    result = model.transcribe(str(audio_path), **kwargs)
    latency_ms = int((time.time() - start) * 1000)
    text = (result.get("text") or "").strip()
    return text, latency_ms, model_downloaded
