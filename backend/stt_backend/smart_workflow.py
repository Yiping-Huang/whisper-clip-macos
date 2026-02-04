from __future__ import annotations

from .prompt_templates import PROMPT_TEMPLATES, SMART_MODE_NORMAL
from .user_glossary import build_glossary_context
from .user_llm_bridge import query_llm


def should_refine(mode: str, smart_refine_enabled: bool) -> bool:
    return smart_refine_enabled and mode in PROMPT_TEMPLATES


def build_user_query(mode: str, transcript: str) -> str:
    template = PROMPT_TEMPLATES[mode].strip()
    transcript = transcript.strip()
    glossary_context = build_glossary_context()
    if glossary_context:
        return f"{template}\n\n{glossary_context}\n\nUser draft:\n{transcript}"
    return f"{template}\n\nUser draft:\n{transcript}"


def refine_transcript(transcript: str, mode: str, smart_refine_enabled: bool) -> tuple[str, bool]:
    normalized_mode = mode or SMART_MODE_NORMAL
    if not should_refine(normalized_mode, smart_refine_enabled):
        return transcript, False

    query = build_user_query(normalized_mode, transcript)
    refined = query_llm(query)
    refined_text = (refined or "").strip()
    if not refined_text:
        return transcript, False
    return refined_text, True
