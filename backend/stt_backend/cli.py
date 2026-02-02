from __future__ import annotations

import argparse
import traceback
from pathlib import Path

from .config import DEFAULT_LANGUAGE, DEFAULT_MODEL, DEFAULT_SAMPLE_RATE, default_config
from .json_io import emit
from .logging_utils import get_logger
from .recorder import capture_loop, start_recording, stop_recording
from .transcriber import transcribe_file


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="stt_backend", description="Whisper Clip backend")
    subparsers = parser.add_subparsers(dest="command", required=True)

    record_parser = subparsers.add_parser("record", help="start/stop local recording")
    mode = record_parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--start", action="store_true")
    mode.add_argument("--stop", action="store_true")
    record_parser.add_argument("--sample-rate", type=int, default=DEFAULT_SAMPLE_RATE)
    record_parser.add_argument("--channels", type=int, default=1)
    record_parser.add_argument("--state-dir", type=Path)
    record_parser.add_argument("--model", default=DEFAULT_MODEL)
    record_parser.add_argument("--language", default=DEFAULT_LANGUAGE)

    toggle_parser = subparsers.add_parser("run", help="toggle recording state")
    toggle_parser.add_argument("--mode", default="toggle", choices=["toggle"])
    toggle_parser.add_argument("--sample-rate", type=int, default=DEFAULT_SAMPLE_RATE)
    toggle_parser.add_argument("--channels", type=int, default=1)
    toggle_parser.add_argument("--state-dir", type=Path)
    toggle_parser.add_argument("--model", default=DEFAULT_MODEL)
    toggle_parser.add_argument("--language", default=DEFAULT_LANGUAGE)

    capture_parser = subparsers.add_parser("_capture", help=argparse.SUPPRESS)
    capture_parser.add_argument("--audio-path", type=Path, required=True)
    capture_parser.add_argument("--sample-rate", type=int, default=DEFAULT_SAMPLE_RATE)
    capture_parser.add_argument("--channels", type=int, default=1)

    return parser


def _normalize_language(language: str) -> str:
    language = (language or "auto").strip().lower()
    return "auto" if language in {"", "auto", "none"} else language


def _state_dir(cli_path: Path | None) -> Path:
    cfg = default_config()
    return cli_path or cfg.state_dir


def _handle_stop(args, logger):
    cfg = default_config()
    state_dir = _state_dir(args.state_dir)
    stop_result = stop_recording(state_dir)
    if stop_result.get("status") != "ok":
        emit(stop_result)
        return 1

    model = stop_result.get("model") or args.model
    language = _normalize_language(stop_result.get("language") or args.language)
    audio_path = Path(stop_result["audio_path"])

    text, latency_ms = transcribe_file(
        audio_path=audio_path,
        model_name=model,
        model_dir=cfg.model_dir,
        language=language,
    )
    payload = {
        "status": "ok",
        "text": text,
        "latency_ms": latency_ms,
        "audio_path": str(audio_path),
        "model": model,
        "language": language,
    }
    emit(payload)
    logger.info("Transcribed audio_path=%s latency_ms=%s", audio_path, latency_ms)
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)
    cfg = default_config()
    logger = get_logger(cfg.log_path)

    try:
        if args.command == "_capture":
            return capture_loop(
                audio_path=args.audio_path,
                sample_rate=args.sample_rate,
                channels=args.channels,
            )

        if args.command == "record":
            state_dir = _state_dir(args.state_dir)
            if args.start:
                payload = start_recording(
                    state_dir=state_dir,
                    sample_rate=args.sample_rate,
                    channels=args.channels,
                    model=args.model,
                    language=_normalize_language(args.language),
                )
                emit(payload)
                return 0 if payload.get("status") == "ok" else 1
            if args.stop:
                return _handle_stop(args, logger)

        if args.command == "run" and args.mode == "toggle":
            state_dir = _state_dir(args.state_dir)
            if (state_dir / "recording_session.json").exists():
                return _handle_stop(args, logger)

            payload = start_recording(
                state_dir=state_dir,
                sample_rate=args.sample_rate,
                channels=args.channels,
                model=args.model,
                language=_normalize_language(args.language),
            )
            emit(payload)
            return 0 if payload.get("status") == "ok" else 1

        emit({"status": "error", "error": "unsupported_command"})
        return 1
    except Exception as exc:
        logger.exception("Backend error: %s", exc)
        emit(
            {
                "status": "error",
                "error": str(exc),
                "trace": traceback.format_exc(limit=5),
            }
        )
        return 1
