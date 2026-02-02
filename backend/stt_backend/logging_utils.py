from __future__ import annotations

import logging
from pathlib import Path


LOGGER_NAME = "stt_backend"


def get_logger(log_path: Path) -> logging.Logger:
    logger = logging.getLogger(LOGGER_NAME)
    if logger.handlers:
        return logger

    logger.setLevel(logging.INFO)
    formatter = logging.Formatter("%(asctime)s %(levelname)s %(message)s")

    file_handler = logging.FileHandler(log_path, encoding="utf-8")
    file_handler.setFormatter(formatter)

    logger.addHandler(file_handler)
    return logger
