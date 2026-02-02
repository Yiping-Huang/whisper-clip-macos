from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path
from threading import Event

STATE_FILE_NAME = "recording_session.json"


def _state_path(state_dir: Path) -> Path:
    return state_dir / STATE_FILE_NAME


def load_state(state_dir: Path) -> dict | None:
    path = _state_path(state_dir)
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def save_state(state_dir: Path, payload: dict) -> None:
    path = _state_path(state_dir)
    path.write_text(json.dumps(payload), encoding="utf-8")


def clear_state(state_dir: Path) -> None:
    path = _state_path(state_dir)
    if path.exists():
        path.unlink()


def process_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def start_recording(
    state_dir: Path,
    sample_rate: int,
    channels: int,
    model: str,
    language: str,
) -> dict:
    existing = load_state(state_dir)
    if existing and process_alive(int(existing.get("pid", -1))):
        return {
            "status": "error",
            "error": "recording_already_running",
            "details": "A recording session is already in progress.",
        }

    audio_path = state_dir / f"recording_{int(time.time() * 1000)}.wav"

    cmd = [
        sys.executable,
        "-m",
        "stt_backend",
        "_capture",
        "--audio-path",
        str(audio_path),
        "--sample-rate",
        str(sample_rate),
        "--channels",
        str(channels),
    ]

    popen_kwargs = {
        "stdout": subprocess.DEVNULL,
        "stderr": subprocess.DEVNULL,
        "stdin": subprocess.DEVNULL,
        "start_new_session": True,
    }
    if os.name == "nt":
        popen_kwargs["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP  # type: ignore[attr-defined]

    proc = subprocess.Popen(cmd, **popen_kwargs)

    payload = {
        "pid": proc.pid,
        "audio_path": str(audio_path),
        "sample_rate": sample_rate,
        "channels": channels,
        "model": model,
        "language": language,
        "started_at": time.time(),
    }
    save_state(state_dir, payload)
    return {
        "status": "ok",
        "recording": True,
        "pid": proc.pid,
        "audio_path": str(audio_path),
    }


def stop_recording(state_dir: Path, timeout_sec: float = 6.0) -> dict:
    state = load_state(state_dir)
    if not state:
        return {
            "status": "error",
            "error": "no_active_recording",
            "details": "No active recording session found.",
        }

    pid = int(state.get("pid", -1))
    if pid <= 0:
        clear_state(state_dir)
        return {
            "status": "error",
            "error": "invalid_state",
            "details": "Stored recording state is invalid.",
        }

    if process_alive(pid):
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass

        deadline = time.time() + timeout_sec
        while process_alive(pid) and time.time() < deadline:
            time.sleep(0.05)

        if process_alive(pid):
            kill_signal = getattr(signal, "SIGKILL", signal.SIGTERM)
            os.kill(pid, kill_signal)

    audio_path = Path(state.get("audio_path", ""))
    clear_state(state_dir)

    if not audio_path.exists() or audio_path.stat().st_size == 0:
        return {
            "status": "error",
            "error": "empty_audio",
            "details": "No audio captured.",
            "audio_path": str(audio_path),
            "model": state.get("model"),
            "language": state.get("language"),
        }

    return {
        "status": "ok",
        "recording": False,
        "audio_path": str(audio_path),
        "model": state.get("model"),
        "language": state.get("language"),
    }


def capture_loop(audio_path: Path, sample_rate: int, channels: int) -> int:
    import sounddevice as sd
    import soundfile as sf

    stop_event = Event()

    def _stop_handler(_signum, _frame):
        stop_event.set()

    signal.signal(signal.SIGTERM, _stop_handler)
    signal.signal(signal.SIGINT, _stop_handler)

    audio_path.parent.mkdir(parents=True, exist_ok=True)

    with sf.SoundFile(
        str(audio_path), mode="w", samplerate=sample_rate, channels=channels, subtype="PCM_16"
    ) as sink:
        def callback(indata, _frames, _time_info, status):
            if status:
                return
            sink.write(indata)

        with sd.InputStream(
            samplerate=sample_rate,
            channels=channels,
            dtype="float32",
            callback=callback,
            blocksize=1024,
        ):
            while not stop_event.is_set():
                sd.sleep(100)

    return 0
