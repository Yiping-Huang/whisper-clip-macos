from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

DEFAULT_SAMPLE_RATE = 16_000
DEFAULT_MODEL = os.getenv("WHISPER_MODEL", "small")
DEFAULT_LANGUAGE = os.getenv("WHISPER_LANGUAGE", "auto")


@dataclass(frozen=True)
class BackendConfig:
    state_dir: Path
    model_dir: Path
    log_path: Path


def default_config() -> BackendConfig:
    project_root = Path(__file__).resolve().parents[2]
    state_dir = Path(os.getenv("WHISPER_CLIP_STATE_DIR", str(project_root / "backend" / "state")))
    model_dir = Path(os.getenv("WHISPER_CLIP_MODEL_DIR", str(project_root / "model")))
    log_path = Path(os.getenv("WHISPER_CLIP_BACKEND_LOG", str(project_root / "backend" / "logs" / "stt_backend.log")))

    state_dir.mkdir(parents=True, exist_ok=True)
    model_dir.mkdir(parents=True, exist_ok=True)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    return BackendConfig(state_dir=state_dir, model_dir=model_dir, log_path=log_path)
